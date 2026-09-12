import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// كباتن المطعم — which riders carry for this shop.
///
/// An owner reaches this from the shop tab to list the couriers carrying for their shop
/// and to attach or detach riders.
///
/// Attaching goes through `attach_courier_by_phone`, which verifies the number belongs
/// to an active courier on the platform. Detaching marks the attachment inactive rather
/// than deleting the row, so re-attaching later re-activates the existing record.
class CourierRosterScreen extends ConsumerStatefulWidget {
  const CourierRosterScreen({super.key, required this.merchantId});

  final String merchantId;

  static const phoneFieldKey = Key('roster.phoneField');
  static const addCourierKey = Key('roster.addCourier');
  static const emptyKey = Key('roster.empty');
  static const confirmDetachKey = Key('roster.confirmDetach');
  static const cancelDetachKey = Key('roster.cancelDetach');

  static Key itemKey(String courierUid) => Key('roster.item.$courierUid');
  static Key detachKey(String courierUid) => Key('roster.detach.$courierUid');

  @override
  ConsumerState<CourierRosterScreen> createState() => _CourierRosterScreenState();
}

class _CourierRosterScreenState extends ConsumerState<CourierRosterScreen> {
  final _phoneController = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }


  Future<void> _addCourier() async {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) return;

    setState(() => _adding = true);
    try {
      final result = await ref
          .read(courierRosterRepositoryProvider)
          .attachCourier(merchantId: widget.merchantId, phone: raw);

      if (!mounted) return;

      switch (result) {
        case Ok():
          _phoneController.clear();
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('تمت إضافة الكابتن.')),
          );
        case Err(:final failure):
          final message = switch (failure) {
            NotFoundFailure() =>
              'مفيش كابتن نشط بالرقم ده. حسابات الكباتن بيفتحها مدير النظام.',
            PermissionFailure() => 'المحل ده مش بتاعك.',
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            _ => 'مقدرناش نضيف الكابتن. جرّب تاني.',
          };
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(message)),
          );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _confirmDetach(CourierRosterItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.luqma;
        return AlertDialog(
          title: const Text('استبعاد الكابتن من المطعم؟'),
          content: Text(
            '${item.name ?? 'الكابتن'} مش هيقدر يستلم طلبات تانية من المحل ده لحد ما تضيفه تاني.',
          ),
          actions: [
            TextButton(
              key: CourierRosterScreen.cancelDetachKey,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('تراجع'),
            ),
            TextButton(
              key: CourierRosterScreen.confirmDetachKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: colors.danger),
              child: const Text('استبعاد'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(courierRosterRepositoryProvider)
        .detachCourier(
          merchantId: widget.merchantId,
          courierUid: item.courierUid,
        );

    if (!mounted) return;

    switch (result) {
      case Ok():
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('تم استبعاد الكابتن من المطعم.')),
        );
      case Err(:final failure):
        final message = switch (failure) {
          OfflineFailure() => 'مفيش نت — جرّب تاني.',
          _ => 'مقدرناش نلغي الربط. جرّب تاني.',
        };
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(message)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final now = ref.watch(clockProvider)();
    final rosterAsync = ref.watch(courierRosterProvider(widget.merchantId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('كباتن المطعم'),
      ),
      body: rosterAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => LuqmaErrorView(
          failure: error is Failure ? error : const UnknownFailure('roster error'),
          onRetry: () => ref.invalidate(courierRosterProvider(widget.merchantId)),
        ),
        data: (roster) {
          // Rows for detached riders are not shown:
          final activeRoster = roster.where((i) => i.isActive).toList();

          return ListView(
            padding: const EdgeInsets.all(Space.gutter),
            children: [
              // ------------------------------------------------ Adding card
              Card(
                elevation: 0,
                color: colors.card,
                shape: const RoundedRectangleBorder(
                  borderRadius: Radii.cardAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'إضافة كابتن للمطعم',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'اكتب رقم تليفون الكابتن لإضافته للمحل. حسابات الكباتن بيفتحها مدير النظام أولاً.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: CourierRosterScreen.phoneFieldKey,
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                hintText: 'رقم تليفون الكابتن',
                                prefixIcon: Icon(Icons.phone_outlined),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: Radii.fieldAll,
                                ),
                              ),
                              onSubmitted: (_) => _addCourier(),
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          FilledButton(
                            key: CourierRosterScreen.addCourierKey,
                            onPressed: _adding ? null : _addCourier,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, Sizes.minTarget),
                            ),
                            child: _adding
                                ? SizedBox(
                                    width: Sizes.iconSm,
                                    height: Sizes.iconSm,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.onBrand,
                                    ),
                                  )
                                : const Text('إضافة'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: Space.lg),
              Text(
                'الطيارين الحاليين (${activeRoster.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: Space.sm),

              // ------------------------------------------------ The list
              if (activeRoster.isEmpty)
                Card(
                  key: CourierRosterScreen.emptyKey,
                  elevation: 0,
                  color: colors.card,
                  shape: const RoundedRectangleBorder(
                    borderRadius: Radii.cardAll,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.two_wheeler_outlined,
                            size: Sizes.emptyIcon,
                            color: colors.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: Space.sm),
                          Text(
                            'مفيش كباتن مضافين للمطعم لسه.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ...activeRoster.map((item) {
                  final isAvailable = item.isAvailableAt(now);

                  return Card(
                    key: CourierRosterScreen.itemKey(item.courierUid),
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: Space.sm),
                    color: colors.card,
                    shape: const RoundedRectangleBorder(
                      borderRadius: Radii.cardAll,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.xs,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: colors.surface,
                        child: Icon(
                          Icons.delivery_dining_rounded,
                          color: colors.brand,
                        ),
                      ),
                      title: Text(
                        item.name ?? 'كابتن',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.phone != null && item.phone!.isNotEmpty) ...[
                            const SizedBox(height: Space.xs),
                            Text(
                              item.phone!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: Space.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.xs,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isAvailable
                                  ? colors.success.withValues(alpha: 0.15)
                                  : colors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isAvailable
                                  ? 'متاح'
                                  : 'متوقف حتى ${luqmaClockTime(item.pausedUntil!, LuqmaStrings.of(context))}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isAvailable
                                    ? colors.success
                                    : colors.accent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        key: CourierRosterScreen.detachKey(item.courierUid),
                        icon: Icon(
                          Icons.person_remove_outlined,
                          color: colors.danger,
                        ),
                        tooltip: 'استبعاد الكابتن',
                        onPressed: () => _confirmDetach(item),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
