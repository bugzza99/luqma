import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'navigation.dart';

/// Courier mode.
///
/// The smallest screen in the product, on purpose. Somebody reads it one-handed at a
/// junction, so a card carries four things and nothing else: where to go, who to call,
/// how much cash to collect, and the one button that is next.
class CourierScreen extends ConsumerStatefulWidget {
  const CourierScreen({super.key});

  static const emptyKey = Key('courier.empty');
  static const errorKey = Key('courier.error');
  static const confirmDeliveredKey = Key('courier.confirmDelivered');
  static const reasonSheetKey = Key('courier.reasonSheet');
  static const pendingKey = Key('courier.pending');
  static const retryKey = Key('courier.retry');
  static const rejectedKey = Key('courier.rejected');
  static const dismissRejectedKey = Key('courier.dismissRejected');

  static const pauseKey = Key('courier.pause');
  static const resumeKey = Key('courier.resume');
  static const pausedKey = Key('courier.paused');
  static const pauseSheetKey = Key('courier.pauseSheet');
  static Key choiceKey(int minutes) => Key('courier.choice.$minutes');
  static const pauseChoices = [30, 60, 120, 240];

  static const carriedShopsKey = Key('courier.carriedShops');
  static Key carriedShopKey(String? id) =>
      Key('courier.carriedShop.${id ?? "platform"}');

  static const customReasonInputKey = Key('courier.customReasonInput');
  static const customReasonSubmitKey = Key('courier.customReasonSubmit');

  static const filterAllKey = Key('courier.filter.all');
  static const filterPlatformKey = Key('courier.filter.platform');
  static Key filterMerchantKey(String id) => Key('courier.filter.$id');

  static Key cardKey(String id) => Key('courier.card.$id');
  static Key cashKey(String id) => Key('courier.cash.$id');
  static Key callKey(String id) => Key('courier.call.$id');
  static Key callMerchantKey(String id) => Key('courier.callMerchant.$id');
  static Key platformBadgeKey(String id) => Key('courier.platform.$id');
  static Key navigateKey(String id) => Key('courier.navigate.$id');
  static Key navigateWazeKey(String id) => Key('courier.navigateWaze.$id');
  static Key outKey(String id) => Key('courier.out.$id');
  static Key deliveredKey(String id) => Key('courier.delivered.$id');
  static Key failedKey(String id) => Key('courier.failed.$id');
  static Key noAddressKey(String id) => Key('courier.noAddress.$id');
  static Key unsentKey(String id) => Key('courier.unsent.$id');
  static Key reasonKey(int index) => Key('courier.reason.$index');

  /// Why a delivery comes back. Six reasons, each with action guidance for the street.
  static const failureReasons = [
    (title: 'العميل مش راضي يرد', nextAction: 'الإدارة هتكلمه'),
    (title: 'العميل رفض الطلب', nextAction: 'الطلب يرجع للمطعم ويتلغي'),
    (title: 'العنوان غلط', nextAction: 'الإدارة هتساعدك توصله'),
    (title: 'معاهوش فلوس كفاية', nextAction: 'ارجع بالطلب وكلّم الإدارة'),
    (title: 'مشكلة في الطلب نفسه', nextAction: 'صوّره قبل ما تسيب العميل'),
    (title: 'مشكلة تانية', nextAction: 'اكتب اللي حصل'),
  ];

  @override
  ConsumerState<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends ConsumerState<CourierScreen> {
  String? _selectedFilter;

  static String _formatClock(DateTime time) {
    int h = time.hour;
    final m = time.minute.toString().padLeft(2, '0');
    final isPm = h >= 12;
    h = h % 12;
    if (h == 0) h = 12;
    final period = isPm ? 'م' : 'ص';
    return '$h:$m $period';
  }

  Future<void> _pause(BuildContext context, String uid) async {
    final now = ref.read(clockProvider)();
    final minutes = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        key: CourierScreen.pauseSheetKey,
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'توقف قد إيه؟',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: Space.xs),
              Text(
                'مش هتوصلك طلبات لحد ما ترجع.',
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(sheetContext).luqma.textSecondary,
                    ),
              ),
              const SizedBox(height: Space.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final choice in CourierScreen.pauseChoices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Sizes.targetGap),
                          child: OutlinedButton(
                            key: CourierScreen.choiceKey(choice),
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(choice),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'حتى ${_formatClock(now.add(Duration(minutes: choice)))}',
                                  style: LuqmaType.button,
                                ),
                                Text(
                                  LuqmaStrings.of(sheetContext).minutes(choice),
                                  style: LuqmaType.caption.copyWith(
                                    color: Theme.of(sheetContext)
                                        .luqma
                                        .textSecondary,
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
            ],
          ),
        ),
      ),
    );

    if (minutes == null || !mounted) return;

    await ref.read(staffRepositoryProvider).setPausedUntil(
          uid,
          ref.read(clockProvider)().add(Duration(minutes: minutes)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffIdentityProvider);
    final colors = Theme.of(context).luqma;
    final now = ref.watch(clockProvider)();

    final staffMember = staff.uid != null
        ? ref.watch(staffMemberProvider(staff.uid!)).value
        : null;
    // Derived on the model, not recomputed here. Whether somebody is available is the
    // same question the merchant's opening hours answer, and this product's rule is that
    // it is derived and never stored — so there is one place that knows the comparison.
    final paused = staffMember != null && !staffMember.isAvailableAt(now)
        ? staffMember.pausedUntil!
        : null;

    final deliveries = ref.watch(carriedDeliveriesProvider);

    void retryDeliveries() {
      ref.invalidate(carriedDeliveriesProvider);
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('التوصيل'),
        actions: [
          if (paused == null && staff.uid != null)
            IconButton(
              key: CourierScreen.pauseKey,
              tooltip: 'مش فاضي دلوقتي',
              icon: const Icon(Icons.pause_circle_outline_rounded),
              onPressed: () => _pause(context, staff.uid!),
            ),
        ],
      ),
      body: Column(
        children: [
          if (paused != null && staff.uid != null)
            _CourierPausedBanner(pausedUntil: paused, courierUid: staff.uid!),
          const LuqmaNotificationBanner(
            reason: 'من غيرها مش هتعرف إن فيه أوردر اتظبط لك للتوصيل غير لما تفتح '
                'التطبيق بنفسك وتشوف.',
            margin: EdgeInsets.all(Space.gutter),
          ),
          const _PendingBanner(),
          const _RejectedBanner(),
          const _CarriedShopsBar(),
          Expanded(
            child: LuqmaAsyncView(
              value: deliveries,
              errorKey: CourierScreen.errorKey,
              onRetry: () => retryDeliveries(),
              empty: LuqmaEmptyView(
                key: CourierScreen.emptyKey,
                icon: Icons.delivery_dining_outlined,
                title: 'مفيش طلبات للتوصيل دلوقتي',
              ),
              isEmpty: (value) => value.isEmpty,
              builder: (context, value) {
                final hasPlatform =
                    value.any((o) => o.deliveryBy == DeliveryBy.platform);
                final shops = <String, String>{};
                for (final o in value) {
                  if (o.deliveryBy != DeliveryBy.platform) {
                    shops[o.merchantId] = o.merchantName;
                  }
                }

                var activeFilter = _selectedFilter;
                if (activeFilter != null) {
                  if (activeFilter == 'platform' && !hasPlatform) {
                    activeFilter = null;
                  } else if (activeFilter != 'platform' &&
                      !shops.containsKey(activeFilter)) {
                    activeFilter = null;
                  }
                }

                final filtered = value.where((o) {
                  if (activeFilter == null) return true;
                  if (activeFilter == 'platform') {
                    return o.deliveryBy == DeliveryBy.platform;
                  }
                  return o.deliveryBy != DeliveryBy.platform &&
                      o.merchantId == activeFilter;
                }).toList();

                return Column(
                  children: [
                    _ShopFilterRow(
                      hasPlatform: hasPlatform,
                      shops: shops,
                      selected: activeFilter,
                      onSelected: (filter) =>
                          setState(() => _selectedFilter = filter),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(Space.gutter),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: Space.md),
                        itemBuilder: (context, i) =>
                            _Card(order: filtered[i], courierUid: staff.uid),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
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

    // The kitchen this rider is collecting from. Null while loading or on failure, in
    // which case the card draws everything else: a rider at a junction does not care why
    // a lookup failed.
    //
    // **Only the telephone.** `merchants` carries a zone and a phone number and no
    // address of any kind — no street, no landmark, no coordinate. Drawing the zone name
    // here would put «إدكو» under a shop and call it where to collect, which is worse
    // than nothing: it looks like information. The shop needs a real address, and that is
    // its own piece of work rather than something to fake on this card.
    final merchant = ref.watch(merchantProvider(order.merchantId)).value;
    final merchantPhone = merchant?.phone;

    // Where this order stands for the person holding it, which is the server's account
    // of it moved on by whatever this phone has queued and not yet sent. Reading the
    // status alone left a run that could be started with no signal and not finished
    // with none — and finishing it is the half that carries the cash.
    final queued = ref.watch(courierPendingWritesProvider).value ??
        const <PendingCourierWrite>[];
    final progress = CourierProgress.of(order.id, order.status, queued);
    final unsent = lastQueuedFor(order.id, queued);

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
                // The shop name has the weight the decision has: a rider carrying for
                // several shops is choosing which kitchen to collect from first.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              order.merchantName,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (order.deliveryBy == DeliveryBy.platform) ...[
                            const SizedBox(width: Space.sm),
                            _PlatformBadge(
                              key: CourierScreen.platformBadgeKey(order.id),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Text(
                      'طلب رقم ${order.orderNumber}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                if (line != null && line.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: Sizes.iconSm,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Text(line, style: theme.textTheme.titleMedium),
                      ),
                    ],
                  )
                else
                  Text(
                    'مفيش عنوان مكتوب — كلّم العميل',
                    key: CourierScreen.noAddressKey(order.id),
                    style: theme.textTheme.titleMedium?.copyWith(color: colors.danger),
                  ),
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    if (merchantPhone != null && merchantPhone.isNotEmpty) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          key: CourierScreen.callMerchantKey(order.id),
                          onPressed: () => openExternalLink(
                            context,
                            ref,
                            Uri(scheme: 'tel', path: merchantPhone),
                            whenUnavailable:
                                'مقدرناش نفتح الاتصال. الرقم $merchantPhone',
                          ),
                          icon: const Icon(Icons.storefront_rounded, size: Sizes.iconSm),
                          label: Text(
                            merchant?.type == MerchantType.homeKitchen ? 'المطبخ' : 'المحل',
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(Sizes.minTarget),
                          ),
                        ),
                      ),
                      const SizedBox(width: Sizes.targetGap),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        key: CourierScreen.callKey(order.id),
                        // The most expensive silent failure in the product: a courier
                        // at the door taps to ring the customer, the dialer refuses,
                        // and nothing on the screen changes.
                        onPressed: () => openExternalLink(
                          context,
                          ref,
                          Uri(scheme: 'tel', path: order.customerPhone),
                          whenUnavailable:
                              'مقدرناش نفتح الاتصال. الرقم ${order.customerPhone}',
                        ),
                        icon: const Icon(Icons.person_rounded, size: Sizes.iconSm),
                        label: Text(order.customerName, overflow: TextOverflow.ellipsis),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(Sizes.minTarget),
                        ),
                      ),
                    ),
                  ],
                ),
                if (line != null && line.isNotEmpty) ...[
                  const SizedBox(height: Sizes.targetGap),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: CourierScreen.navigateKey(order.id),
                          onPressed: () => ref.read(mapNavigatorProvider).navigateTo(
                                line,
                                lat: order.address?.lat,
                                lng: order.address?.lng,
                                app: MapApp.googleMaps,
                              ),
                          icon: const Icon(Icons.navigation_rounded, size: Sizes.iconSm),
                          label: const Text('Google Maps', overflow: TextOverflow.ellipsis),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(Sizes.minTarget),
                          ),
                        ),
                      ),
                      const SizedBox(width: Sizes.targetGap),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: CourierScreen.navigateWazeKey(order.id),
                          onPressed: () => ref.read(mapNavigatorProvider).navigateTo(
                                line,
                                lat: order.address?.lat,
                                lng: order.address?.lng,
                                app: MapApp.waze,
                              ),
                          icon: const Icon(Icons.explore_outlined, size: Sizes.iconSm),
                          label: const Text('Waze', overflow: TextOverflow.ellipsis),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(Sizes.minTarget),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.md),
                if (unsent != null) ...[
                  // Said before the buttons, not after: the courier is about to act on
                  // the state above, and «هيتبعت» is what makes moving the card forward
                  // an honest thing to do rather than a claim the server never heard.
                  Row(
                    key: CourierScreen.unsentKey(order.id),
                    children: [
                      Icon(Icons.cloud_off_outlined,
                          size: Sizes.iconSm, color: colors.textSecondary),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          switch (unsent) {
                            CourierWriteKind.onTheWay =>
                              'بدأت التوصيل — هيتبعت أول ما النت يرجع',
                            CourierWriteKind.delivered =>
                              'التسليم اتسجّل — هيتبعت أول ما النت يرجع',
                            CourierWriteKind.failed =>
                              'اللي حصل اتسجّل — هيتبعت أول ما النت يرجع',
                          },
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                ],
                if (progress == CourierProgress.toCollect)
                  FilledButton(
                    key: CourierScreen.outKey(order.id),
                    onPressed: courierUid == null
                        ? null
                        : () => _submit(
                              context,
                              ref
                                  .read(courierWriteQueueProvider)
                                  .markOnTheWay(order.id, courierUid: courierUid!),
                            ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(strings.startedDelivery),
                  )
                // `finished` draws neither: this phone has already recorded the end of
                // this delivery, and a second tap would queue the same one twice.
                else if (progress == CourierProgress.onTheRoad) ...[
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

    _submit(
      context,
      ref.read(courierWriteQueueProvider).markDelivered(order.id),
    );
  }

  Future<void> _reportFailure(BuildContext context, WidgetRef ref) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).luqma;
        final theme = Theme.of(sheetContext);

        return SafeArea(
          key: CourierScreen.reasonSheetKey,
          child: Padding(
            padding: EdgeInsets.only(
              left: Space.gutter,
              right: Space.gutter,
              top: Space.gutter,
              bottom:
                  MediaQuery.of(sheetContext).viewInsets.bottom + Space.gutter,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('حصل إيه؟', style: theme.textTheme.titleLarge),
                const SizedBox(height: Space.md),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < CourierScreen.failureReasons.length; i++)
                          if (i == 5)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: Sizes.targetGap),
                              child: _CustomReasonWidget(
                                reason: CourierScreen.failureReasons[5],
                                onSubmit: (text) =>
                                    Navigator.of(sheetContext).pop(text),
                              ),
                            )
                          else
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: Sizes.targetGap),
                              child: OutlinedButton(
                                key: CourierScreen.reasonKey(i),
                                onPressed: () => Navigator.of(sheetContext)
                                    .pop(CourierScreen.failureReasons[i].title),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Space.md,
                                    vertical: Space.sm,
                                  ),
                                  minimumSize: const Size.fromHeight(56),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      CourierScreen.failureReasons[i].title,
                                      style: LuqmaType.button,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      CourierScreen.failureReasons[i].nextAction,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colors.textSecondary,
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
              ],
            ),
          ),
        );
      },
    );

    if (reason == null || !context.mounted) return;

    _submit(
      context,
      ref
          .read(courierWriteQueueProvider)
          .markFailed(order.id, reason: reason),
    );
  }

  /// Says what happened to the tap. Queued is the honest middle: the write is saved and
  /// will go out when the connection returns, so the courier is told that rather than
  /// "failed" — the tap did not die, it is waiting.
  Future<void> _submit(
    BuildContext context,
    Future<CourierSubmitOutcome> pending,
  ) async {
    final outcome = await pending;
    if (!context.mounted) return;

    if (outcome case CourierRejected(:final failure)) {
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
    } else if (outcome case CourierQueued()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هيتبعت أول ما النت يرجع.')),
      );
    }
  }
}


/// The one banner that must never be missing: a courier whose tap was queued has to see
/// that it is still waiting, and be given a way to try again. Nothing else on this
/// screen is silently lost, and neither is this.
class _PendingBanner extends ConsumerWidget {
  const _PendingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref.watch(courierPendingWritesProvider).value ?? const [];
    if (pending.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      key: CourierScreen.pendingKey,
      width: double.infinity,
      color: colors.accent,
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: Sizes.iconMd, color: colors.onAccent),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'فيه ${pending.length} تحديث هيتبعت أول ما النت يرجع',
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.onAccent),
            ),
          ),
          TextButton(
            key: CourierScreen.retryKey,
            onPressed: () => ref.read(courierWriteQueueProvider).flush(),
            style: TextButton.styleFrom(foregroundColor: colors.onAccent),
            child: const Text('حاول تاني'),
          ),
        ],
      ),
    );
  }
}
/// The other half of the promise the banner above makes.
///
/// `_PendingBanner` says "هيتبعت أول ما النت يرجع". When the replay is refused — the
/// order was finished by somebody else while there was no signal — that write is
/// correctly not retried for ever, and used to vanish with it. The count fell by one and
/// read as sent, while the cash for that order was already in the courier's pocket.
///
/// So it is said out loud, in the colour the rest of the app reserves for something
/// being wrong, and it stays until the courier dismisses it.
class _RejectedBanner extends ConsumerWidget {
  const _RejectedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rejected = ref.watch(courierRejectedWritesProvider).value ?? const [];
    if (rejected.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      key: CourierScreen.rejectedKey,
      width: double.infinity,
      // A white card with `danger` on it, which is how every other error in this product
      // is drawn. There is no `onDanger` token, and there is no token because nothing
      // here puts text on a red field — inventing that pairing in a screen would be a
      // colour written outside `luqma_core` and a contrast ratio nobody has checked.
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
      child: Row(
        children: [
          Icon(Icons.report_problem_outlined,
              size: Sizes.iconMd, color: colors.danger),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              '${rejected.length} تحديث محصلش — الأوردر اتغيّر. كلّم الإدارة.',
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.danger),
            ),
          ),
          TextButton(
            key: CourierScreen.dismissRejectedKey,
            onPressed: () => ref.read(courierWriteQueueProvider).clearRejected(),
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            child: const Text('تمام'),
          ),
        ],
      ),
    );
  }
}

/// A small badge on platform orders so couriers carrying both kinds in one queue see which is which.
class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: colors.brand,
        borderRadius: Radii.pillAll,
      ),
      child: Text(
        'منصة',
        style: LuqmaType.caption.copyWith(
          color: colors.onBrand,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ShopFilterRow extends StatelessWidget {
  const _ShopFilterRow({
    required this.hasPlatform,
    required this.shops,
    required this.selected,
    required this.onSelected,
  });

  final bool hasPlatform;
  final Map<String, String> shops;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.xs,
      ),
      child: Row(
        children: [
          ChoiceChip(
            key: CourierScreen.filterAllKey,
            label: const Text('الكل'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          if (hasPlatform) ...[
            const SizedBox(width: Space.sm),
            ChoiceChip(
              key: CourierScreen.filterPlatformKey,
              label: const Text('المنصة'),
              selected: selected == 'platform',
              onSelected: (_) => onSelected('platform'),
            ),
          ],
          for (final entry in shops.entries) ...[
            const SizedBox(width: Space.sm),
            ChoiceChip(
              key: CourierScreen.filterMerchantKey(entry.key),
              label: Text(entry.value),
              selected: selected == entry.key,
              onSelected: (_) => onSelected(entry.key),
            ),
          ],
        ],
      ),
    );
  }
}

class _CourierPausedBanner extends ConsumerWidget {
  const _CourierPausedBanner({
    required this.pausedUntil,
    required this.courierUid,
  });

  final DateTime pausedUntil;
  final String courierUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    final now = ref.watch(clockProvider)();
    final left = pausedUntil.difference(now).inMinutes + 1;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: CourierScreen.pausedKey,
      width: double.infinity,
      color: colors.accent,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.pause_circle_outline_rounded,
            size: Sizes.iconMd,
            color: colors.onAccent,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              'متوقف — هترجع بعد ${strings.minutes(left)} (${_CourierScreenState._formatClock(pausedUntil)})',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.onAccent),
            ),
          ),
          OutlinedButton(
            key: CourierScreen.resumeKey,
            onPressed: () => ref
                .read(staffRepositoryProvider)
                .setPausedUntil(courierUid, null),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.onAccent,
              side: BorderSide(color: colors.onAccent.withValues(alpha: 0.5)),
              minimumSize: const Size(0, Sizes.minTarget),
            ),
            child: const Text('ارجع اشتغل'),
          ),
        ],
      ),
    );
  }
}

class _CarriedShopsBar extends ConsumerWidget {
  const _CarriedShopsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carried = ref.watch(carriedMerchantsProvider).value ?? const [];
    if (carried.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      key: CourierScreen.carriedShopsKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.xs,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(
              Icons.storefront_outlined,
              size: Sizes.iconSm,
              color: colors.textSecondary,
            ),
            const SizedBox(width: Space.xs),
            Text(
              'بتوصّل لـ:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: Space.sm),
            for (final id in carried) ...[
              Container(
                key: CourierScreen.carriedShopKey(id),
                margin: const EdgeInsets.only(left: Space.xs),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: Radii.pillAll,
                  border: Border.all(color: colors.hairline),
                ),
                child: id == null
                    ? Text(
                        'المنصة',
                        style: LuqmaType.caption.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : _CarriedMerchantName(merchantId: id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CarriedMerchantName extends ConsumerWidget {
  const _CarriedMerchantName({required this.merchantId});

  final String merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchant = ref.watch(merchantProvider(merchantId)).value;
    final colors = Theme.of(context).luqma;

    return Text(
      merchant?.name ?? '...',
      style: LuqmaType.caption.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _CustomReasonWidget extends StatefulWidget {
  const _CustomReasonWidget({
    required this.reason,
    required this.onSubmit,
  });

  final ({String title, String nextAction}) reason;
  final ValueChanged<String> onSubmit;

  @override
  State<_CustomReasonWidget> createState() => _CustomReasonWidgetState();
}

class _CustomReasonWidgetState extends State<_CustomReasonWidget> {
  bool _expanded = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    if (!_expanded) {
      return OutlinedButton(
        key: CourierScreen.reasonKey(5),
        onPressed: () => setState(() => _expanded = true),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          minimumSize: const Size.fromHeight(56),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.reason.title, style: LuqmaType.button),
            const SizedBox(height: 2),
            Text(
              widget.reason.nextAction,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.reason.title,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'إلغاء',
                icon: const Icon(Icons.close, size: Sizes.iconSm),
                onPressed: () => setState(() => _expanded = false),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          TextField(
            key: CourierScreen.customReasonInputKey,
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'اكتب اللي حصل بالتفصيل...',
              border: OutlineInputBorder(borderRadius: Radii.cardAll),
            ),
          ),
          const SizedBox(height: Space.md),
          FilledButton(
            key: CourierScreen.customReasonSubmitKey,
            onPressed: () {
              final text = _controller.text.trim();
              if (text.isNotEmpty) {
                widget.onSubmit(text);
              }
            },
            child: const Text('تأكيد وإرسال'),
          ),
        ],
      ),
    );
  }
}

