import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'navigation.dart';

/// Courier mode.
///
/// The smallest screen in the product, on purpose. Somebody reads it one-handed at a
/// junction, so a card carries four things and nothing else: where to go, who to call,
/// how much cash to collect, and the one button that is next.
class CourierScreen extends ConsumerWidget {
  const CourierScreen({super.key});

  static const emptyKey = Key('courier.empty');
  static const errorKey = Key('courier.error');
  static const confirmDeliveredKey = Key('courier.confirmDelivered');
  static const reasonSheetKey = Key('courier.reasonSheet');

  static Key cardKey(String id) => Key('courier.card.$id');
  static Key cashKey(String id) => Key('courier.cash.$id');
  static Key callKey(String id) => Key('courier.call.$id');
  static Key navigateKey(String id) => Key('courier.navigate.$id');
  static Key outKey(String id) => Key('courier.out.$id');
  static Key deliveredKey(String id) => Key('courier.delivered.$id');
  static Key failedKey(String id) => Key('courier.failed.$id');
  static Key noAddressKey(String id) => Key('courier.noAddress.$id');
  static Key reasonKey(int index) => Key('courier.reason.$index');

  /// Why a delivery comes back. Chosen, not typed: this gets answered in the street.
  static const failureReasons = [
    'العميل مش موجود',
    'العميل مش بيرد',
    'العنوان غلط',
    'العميل رفض الطلب',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffIdentityProvider);
    final colors = Theme.of(context).luqma;

    // A merchant's courier carries that merchant's orders; the platform's carries the
    // home kitchens and the merchants that do not deliver.
    final deliveries = staff.scope == StaffScope.platform
        ? ref.watch(platformDeliveriesProvider(ref.watch(currentCityProvider)))
        : staff.merchantId == null
            ? const AsyncValue<List<Order>>.data([])
            : ref.watch(merchantDeliveriesProvider(staff.merchantId!));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('التوصيل')),
      body: switch (deliveries) {
        // First, and on `hasError`: a stream that fails before it has ever emitted stays
        // AsyncLoading with the error hanging off it.
        AsyncValue(hasError: true, :final error?) => _Error(failure: error),
        AsyncValue(hasValue: true, :final value?) when value.isEmpty => const _Empty(),
        AsyncValue(hasValue: true, :final value?) => ListView.separated(
            padding: const EdgeInsets.all(Space.gutter),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.md),
            itemBuilder: (context, i) => _Card(order: value[i], courierUid: staff.uid),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.order, required this.courierUid});

  final Order order;
  final String? courierUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final zones = ref.watch(zonesProvider).value ?? const <Zone>[];
    final zoneName =
        zones.where((z) => z.id == order.zoneId).firstOrNull?.name ?? '';
    final line = order.address?.format(zoneName: zoneName);
    final onTheRoad = order.status == OrderStatus.outForDelivery;

    return Container(
      key: CourierScreen.cardKey(order.id),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The number to collect, first and loudest. Everything else on this card is
          // about getting there; this is the one thing that has to be exactly right.
          Container(
            key: CourierScreen.cashKey(order.id),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(top: Radii.card),
            ),
            child: Row(
              children: [
                Icon(Icons.payments_rounded, color: colors.price, size: Sizes.iconMd),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    strings.collectFromCustomer,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  strings.price(order.pricing.total),
                  style: LuqmaType.display.copyWith(
                    color: colors.price,
                    fontSize: 26,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'طلب رقم ${order.orderNumber} · ${order.merchantName}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: Space.sm),
                if (line != null && line.isNotEmpty)
                  Text(line, style: theme.textTheme.titleMedium)
                else
                  Text(
                    'مفيش عنوان مكتوب — كلّم العميل',
                    key: CourierScreen.noAddressKey(order.id),
                    style: theme.textTheme.titleMedium?.copyWith(color: colors.danger),
                  ),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: CourierScreen.callKey(order.id),
                        onPressed: () => launchUrl(
                          Uri(scheme: 'tel', path: order.customerPhone),
                        ),
                        icon: const Icon(Icons.phone_rounded, size: Sizes.iconSm),
                        label: Text(order.customerName, overflow: TextOverflow.ellipsis),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(Sizes.minTarget),
                        ),
                      ),
                    ),
                    if (line != null && line.isNotEmpty) ...[
                      const SizedBox(width: Sizes.targetGap),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: CourierScreen.navigateKey(order.id),
                          onPressed: () =>
                              ref.read(mapNavigatorProvider).navigateTo(line),
                          icon: const Icon(Icons.navigation_rounded, size: Sizes.iconSm),
                          label: Text(strings.navigateToCustomer,
                              overflow: TextOverflow.ellipsis),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(Sizes.minTarget),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Space.md),
                if (!onTheRoad)
                  FilledButton(
                    key: CourierScreen.outKey(order.id),
                    onPressed: courierUid == null
                        ? null
                        : () => _report(
                              context,
                              pending: ref
                                  .read(courierOrderRepositoryProvider)
                                  .markOnTheWay(order.id, courierUid: courierUid!),
                            ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(strings.startedDelivery),
                  )
                else ...[
                  FilledButton(
                    key: CourierScreen.deliveredKey(order.id),
                    onPressed: () => _confirmDelivered(context, ref, strings),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.success,
                      foregroundColor: colors.onBrand,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(strings.markDelivered),
                  ),
                  const SizedBox(height: Sizes.targetGap),
                  TextButton(
                    key: CourierScreen.failedKey(order.id),
                    onPressed: () => _reportFailure(context, ref),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.danger,
                      minimumSize: const Size.fromHeight(Sizes.minTarget),
                    ),
                    child: const Text('التسليم ما تمّش'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelivered(
    BuildContext context,
    WidgetRef ref,
    LuqmaStrings strings,
  ) async {
    // Asked once, with the amount repeated. Delivered means the cash changed hands and
    // the order can never be moved again; asking costs a second, getting it wrong costs
    // the money.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: CourierScreen.confirmDeliveredKey,
        title: const Text('استلمت الفلوس؟'),
        content: Text(
          'المفروض تستلم ${strings.price(order.pricing.total)} من '
          '${order.customerName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لسه'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('اه، تم'),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false) || !context.mounted) return;

    _report(
      context,
      pending: ref.read(courierOrderRepositoryProvider).markDelivered(order.id),
    );
  }

  Future<void> _reportFailure(BuildContext context, WidgetRef ref) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        key: CourierScreen.reasonSheetKey,
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('حصل إيه؟', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: Space.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < CourierScreen.failureReasons.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Sizes.targetGap),
                          child: OutlinedButton(
                            key: CourierScreen.reasonKey(i),
                            onPressed: () => Navigator.of(sheetContext)
                                .pop(CourierScreen.failureReasons[i]),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                            ),
                            child: Text(
                              CourierScreen.failureReasons[i],
                              style: LuqmaType.button,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (reason == null || !context.mounted) return;

    _report(
      context,
      pending: ref
          .read(courierOrderRepositoryProvider)
          .markFailed(order.id, reason: reason),
    );
  }

  /// Says something when a write is refused. A courier in the street tapping a button
  /// that appears to do nothing will tap it again, and then phone somebody.
  Future<void> _report(
    BuildContext context, {
    required Future<Result<void>> pending,
  }) async {
    final result = await pending;
    if (!context.mounted) return;

    if (result case Err(:final failure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (failure) {
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            ConflictFailure() => 'الطلب ده اتغير. حدّث الشاشة.',
            PermissionFailure() => 'الطلب ده مع حد تاني.',
            _ => 'مقدرناش نحفظ ده. جرّب تاني.',
          }),
        ),
      );
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: CourierScreen.emptyKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delivery_dining_outlined,
              size: 56,
              color: theme.luqma.textSecondary,
            ),
            const SizedBox(height: Space.lg),
            Text(
              'مفيش طلبات للتوصيل دلوقتي',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.failure});

  final Object failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: CourierScreen.errorKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: theme.luqma.danger),
            const SizedBox(height: Space.lg),
            // Never "nothing to deliver". A courier who reads a dropped connection that
            // way goes home.
            Text(
              'مش قادرين نوصل للطلبات',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              switch (failure) {
                OfflineFailure() => 'شوف النت. ممكن يكون في طلبات مستنية.',
                PermissionFailure() => 'الحساب ده مالوش صلاحية توصيل.',
                _ => 'حصل خطأ. جرّب تاني بعد شوية.',
              },
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.luqma.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
