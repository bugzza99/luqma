import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pending_collection.dart';

/// حسابات المناديب — who owes the platform, and recording the cash when it is handed over.
///
/// The other half of `20261017000000`. Without this screen the platform charges couriers
/// and has no way to say anybody paid, so a balance only ever rises — which is the same
/// shape as the eight phases the platform spent recording what it would charge and
/// charging nothing, arrived at from the opposite direction.
///
/// It is the owner's side of the rider's own كشف الحساب: the same `courier_settlements`
/// and `courier_commission_payments` rows, read through the same policies. One ledger, so
/// the conversation at the end of the week has one set of numbers in it.
class CourierBillingScreen extends ConsumerWidget {
  const CourierBillingScreen({super.key});

  static const emptyKey = Key('courierBilling.empty');
  static const listKey = Key('courierBilling.list');
  static const amountKey = Key('courierBilling.amount');
  static const confirmKey = Key('courierBilling.confirm');
  static const frozenKey = Key('courierBilling.frozen');

  static Key rowKey(String uid) => Key('courierBilling.row.$uid');
  static Key collectKey(String uid) => Key('courierBilling.collect.$uid');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    final couriers = ref.watch(couriersOutstandingProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('حسابات المناديب')),
      body: switch (couriers) {
        // hasError first: a provider that fails before it has ever emitted stays
        // AsyncLoading with the error hanging off it, and the error arm never fires.
        AsyncValue(hasError: true, :final error) => LuqmaErrorView(
            failure: error,
            onRetry: () => ref.invalidate(couriersOutstandingProvider),
          ),
        AsyncValue(value: null) => const Center(child: CircularProgressIndicator()),
        AsyncValue(value: final rows!) when rows.isEmpty => const _Empty(),
        AsyncValue(value: final rows!) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(couriersOutstandingProvider),
            child: ListView.separated(
              key: listKey,
              padding: const EdgeInsets.all(Space.gutter),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
              itemBuilder: (context, i) => _CourierRow(balance: rows[i]),
            ),
          ),
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    return Center(
      key: CourierBillingScreen.emptyKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Text(
          'كل المناديب حساباتهم مظبوطة، مفيش حد عليه حاجة.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

class _CourierRow extends ConsumerStatefulWidget {
  const _CourierRow({required this.balance});

  final CourierBalance balance;

  @override
  ConsumerState<_CourierRow> createState() => _CourierRowState();
}

class _CourierRowState extends ConsumerState<_CourierRow> {
  bool _busy = false;

  PendingCollections get _pending =>
      PendingCollections(SharedPreferencesAsync(), kind: 'courier');

  /// A v4 uuid, made once per collection and kept across every retry of it.
  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
        '-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _collect() async {
    final balance = widget.balance;
    final strings = LuqmaStrings.of(context);

    // An attempt whose reply was lost. Its amount is not editable and its id is reused:
    // if the first request landed, the server answers with the receipt it already holds
    // and moves nothing; if it did not, this is the first one to arrive. Either way the
    // cash is recorded exactly once.
    final stored = await _pending.load(balance.uid);
    if (!mounted) return;

    final controller = TextEditingController(
      text: stored != null
          ? Money.format(stored.amount)
          : (balance.owed > 0 ? Money.format(balance.owed) : ''),
    );

    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('تحصيل من ${balance.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stored != null) ...[
              Text(
                key: CourierBillingScreen.frozenKey,
                'في محاولة تحصيل سابقة بـ ${strings.price(stored.amount)} مردّتش. '
                'اضغط تأكيد تاني — لو كانت وصلت مش هتتسجّل مرتين.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              const SizedBox(height: Space.md),
            ],
            TextField(
              key: CourierBillingScreen.amountKey,
              controller: controller,
              // Frozen with its receipt. An editable field on a retry is how a new figure
              // gets sent under an old receipt id.
              readOnly: stored != null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ بالجنيه'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: CourierBillingScreen.confirmKey,
            onPressed: () {
              final parsed = stored?.amount ?? Money.parse(controller.text);
              if (parsed == null || parsed <= 0) return;
              Navigator.of(dialogContext).pop(parsed);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (amount == null || !mounted) return;

    // Frozen together, and written down *before* the request. A record made afterwards
    // is a record that does not exist for the one failure it was built for.
    final receiptId = stored?.receiptId ?? _uuid();
    await _pending.save(
      balance.uid,
      PendingCollection(receiptId: receiptId, amount: amount),
    );

    setState(() => _busy = true);
    final result = await ref.read(courierStatementRepositoryProvider).recordPayment(
          courierUid: balance.uid,
          amount: amount,
          receiptId: receiptId,
        );
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case Ok(:final value):
        await _pending.clear(balance.uid);
        if (!mounted) return;
        ref.invalidate(couriersOutstandingProvider);
        ref.invalidate(courierPaymentsProvider(courierUid: balance.uid));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value.remaining > 0
                  ? 'اتسجّل. فاضل عليه ${strings.price(value.remaining)}'
                  : value.remaining < 0
                      ? 'اتسجّل. بقى ليه رصيد ${strings.price(-value.remaining)}'
                      : 'اتسجّل. حسابه بقى مظبوط',
            ),
          ),
        );
      case Err(:final failure):
        // The pending record stays. The reply not arriving is not the same as the money
        // not moving, and the next attempt has to carry the same id to find out.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure is OfflineFailure
                  ? 'مفيش نت. التحصيل محفوظ، جرّب تاني لما الشبكة ترجع.'
                  : 'مقدرناش نسجّل التحصيل. جرّب تاني.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final balance = widget.balance;
    final owes = balance.owed > 0;

    return Container(
      key: CourierBillingScreen.rowKey(balance.uid),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(balance.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: Space.xs),
                    Text(balance.phone,
                        style: LuqmaType.caption.copyWith(color: colors.textSecondary)),
                    if (!balance.isActive) ...[
                      const SizedBox(height: Space.xs),
                      // A dismissed courier can still owe, and the debt survives them
                      // leaving. Saying so stops the owner ringing a number that no
                      // longer works and assuming the balance is a mistake.
                      Text('موقوف',
                          style: LuqmaType.caption.copyWith(color: colors.danger)),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    strings.price(owes ? balance.owed : -balance.owed),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: owes ? colors.price : colors.success,
                    ),
                  ),
                  Text(
                    // In words. A minus sign in front of a figure the platform owes gets
                    // read as a debt at the wrong moment.
                    owes ? 'عليه' : 'رصيد ليه',
                    style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          if (owes) ...[
            const SizedBox(height: Space.md),
            FilledButton(
              key: CourierBillingScreen.collectKey(balance.uid),
              onPressed: _busy ? null : _collect,
              child: Text(_busy ? 'لحظة…' : 'سجّل تحصيل'),
            ),
          ],
        ],
      ),
    );
  }
}
