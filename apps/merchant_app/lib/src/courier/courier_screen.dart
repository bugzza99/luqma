import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'courier_statement_screen.dart';
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
  static const signOutKey = Key('courier.signOut');
  static const confirmSignOutKey = Key('courier.confirmSignOut');
  static const unsentWarningKey = Key('courier.unsentWarning');

  static const pauseKey = Key('courier.pause');
  static const resumeKey = Key('courier.resume');
  static const pausedKey = Key('courier.paused');
  static const pauseSheetKey = Key('courier.pauseSheet');
  static Key choiceKey(int minutes) => Key('courier.choice.$minutes');
  static const pauseChoices = [30, 60, 120, 240];

  static const carriedShopsKey = Key('courier.carriedShops');
  static Key carriedShopKey(String? id) =>
      Key('courier.carriedShop.${id ?? "platform"}');

  static const summaryKey = Key('courier.summary');
  static const summaryDeliveredKey = Key('courier.summary.delivered');
  static const summaryReturnedKey = Key('courier.summary.returned');
  static const summaryCashKey = Key('courier.summary.cash');
  static Key summaryShopKey(String id) => Key('courier.summary.shop.$id');

  static const customReasonInputKey = Key('courier.customReasonInput');
  static const customReasonSubmitKey = Key('courier.customReasonSubmit');

  static const filterAllKey = Key('courier.filter.all');
  static const filterPlatformKey = Key('courier.filter.platform');
  static Key filterMerchantKey(String id) => Key('courier.filter.$id');

  static Key cardKey(String id) => Key('courier.card.$id');
  static Key cashKey(String id) => Key('courier.cash.$id');

  /// Whose money the cash above is: the shop's, the rider's, and the platform's share.
  static Key cutKey(String id) => Key('courier.cut.$id');

  /// The span the summary card is showing: today, this week, or this month.
  static Key spanKey(String span) => Key('courier.span.$span');
  static const summaryNetKey = Key('courier.summary.net');
  static const statementKey = Key('courier.statement');
  static const summaryCommissionKey = Key('courier.summary.commission');
  static Key callKey(String id) => Key('courier.call.$id');
  static Key callMerchantKey(String id) => Key('courier.callMerchant.$id');
  static Key shopAddressKey(String id) => Key('courier.shopAddress.$id');
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
                            // Both halves flexible, not a `spaceBetween` of two fixed
                            // texts. The hour is the thing being chosen and the duration
                            // is the gloss on it; at 15sp the pair overflowed a narrow
                            // phone by fifteen pixels, and the half that would have been
                            // clipped is the one that says when the rider is back.
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'حتى ${luqmaClockTime(now.add(Duration(minutes: choice)), LuqmaStrings.of(sheetContext))}',
                                    style: LuqmaType.button,
                                  ),
                                ),
                                const SizedBox(width: Space.sm),
                                Flexible(
                                  child: Text(
                                    LuqmaStrings.of(sheetContext).minutes(choice),
                                    textAlign: TextAlign.end,
                                    overflow: TextOverflow.ellipsis,
                                    style: LuqmaType.bodySmall.copyWith(
                                      color: Theme.of(sheetContext)
                                          .luqma
                                          .textSecondary,
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
            ],
          ),
        ),
      ),
    );

    if (minutes == null || !mounted) return;

    final result = await ref.read(staffRepositoryProvider).setPausedUntil(
          uid,
          ref.read(clockProvider)().add(Duration(minutes: minutes)),
        );
    // Said when it did not land (C6): a rider who thinks they are off the queue and is
    // not is sent orders they will not take.
    if (result.failureOrNull != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('مقدرناش نوقفك — اتأكد من النت وجرّب تاني.')),
      );
    }
  }

  /// The way off this account, which courier mode never had.
  ///
  /// On a shared shop handset the only other way was Android's "Clear storage" — which
  /// deletes the very writes the queue exists to keep, cash already collected. Signing
  /// out deletes nothing: the queue is stored under this account and loads again, and
  /// sends, the next time this account signs in on this phone. So a courier with taps
  /// still waiting is told exactly that before they go, and not told anything scarier.
  Future<void> _confirmSignOut(BuildContext context) async {
    final queue = ref.read(courierWriteQueueProvider);
    await queue.load();
    final unsent = queue.pendingCount;
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجّل خروج؟'),
        content: unsent > 0
            ? Text(
                'فيه $unsent تحديث لسه متبعتش. هيفضل مستني على التليفون ده لحد ما '
                'تدخل بحسابك ده تاني، وساعتها يتبعت.',
                key: CourierScreen.unsentWarningKey,
              )
            : const Text(
                'مش هتوصلك طلبات توصيل على التليفون ده لحد ما تدخل تاني.',
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لا'),
          ),
          FilledButton(
            key: CourierScreen.confirmSignOutKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('اخرج'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      // The push token comes off the account through `keepPushTokenRegistered`, which is
      // watching the session — the same as the shop screen's sign-out.
      await ref.read(authServiceProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    // A pickup notification is a delivery for any of the courier's shops; showing them all
    // is what makes sure the one it announced is on the screen.
    return LuqmaTappedNotification(
      onOpen: (_) => setState(() => _selectedFilter = null),
      child: _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
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
      ref.invalidate(courierDaySummaryProvider);
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
          IconButton(
            key: CourierScreen.signOutKey,
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _confirmSignOut(context),
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
          const _CourierDaySummaryView(),
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
    final shopZone =
        zones.where((z) => z.id == merchant?.zoneId).firstOrNull?.name;
    final shopAddress = merchant?.formatAddress(zoneName: shopZone);

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
          // Directly under the figure it divides, because the two are one thought: this
          // is what the rider does with the money they are about to be handed.
          _CutBreakdown(order: order),
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
                if (shopAddress != null && shopAddress.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Row(
                    key: CourierScreen.shopAddressKey(order.id),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        size: Sizes.iconSm,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Text(
                          shopAddress,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
                        // Not when there is no number to ring: an account deleted
                        // under an order leaves «حساب محذوف» where the phone was, and
                        // the dialer was handed that text (A9 now refuses the deletion
                        // while an order is live; older rows can still carry it).
                        onPressed: !Phone.isValidEgyptianMobile(order.customerPhone)
                            ? null
                            : () => openExternalLink(
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
                              ref,
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
      ref,
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
      ref,
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
    WidgetRef ref,
    Future<CourierSubmitOutcome> pending,
  ) async {
    final outcome = await pending;
    if (!context.mounted) return;
    ref.invalidate(courierDaySummaryProvider);

    if (outcome case CourierRejected(:final failure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (failure) {
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            ConflictFailure() => 'الطلب ده اتغير. حدّث الشاشة.',
            PermissionFailure() => 'الطلب ده مع حد تاني.',
            // The order is no longer this account's to see — a courier dismissed
            // mid-shift, whose reads the database now filters away. «جرّب تاني» would send
            // them round a door that will not open.
            NotFoundFailure() => 'الطلب ده مبقاش ظاهر ليك. كلّم الإدارة.',
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
            // Straight to the queue, which joins a pass already running rather than
            // starting a second one over the same writes.
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
              'متوقف — هترجع بعد ${strings.minutes(left)} (${luqmaClockTime(pausedUntil, strings)})',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.onAccent),
            ),
          ),
          OutlinedButton(
            key: CourierScreen.resumeKey,
            onPressed: () async {
              final result = await ref
                  .read(staffRepositoryProvider)
                  .setPausedUntil(courierUid, null);
              if (result.failureOrNull != null && context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('مقدرناش نرجّعك — اتأكد من النت وجرّب تاني.'),
                  ),
                );
              }
            },
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

/// What the rider did today. If nothing has happened yet on this shift (0 delivered,
/// 0 returned, 0 cash), the rider is told nothing — no empty card, no heading, no error
/// card. When work has happened, shows deliveries, returns, cash in hand, and the per-shop split.
/// Which stretch of work the summary card is showing.
enum _Span { today, week, month }

class _CourierDaySummaryView extends ConsumerStatefulWidget {
  const _CourierDaySummaryView();

  @override
  ConsumerState<_CourierDaySummaryView> createState() => _CourierDaySummaryViewState();
}

class _CourierDaySummaryViewState extends ConsumerState<_CourierDaySummaryView> {
  _Span _span = _Span.today;

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(courierDaySummaryProvider);
    final summary = summaryAsync.value;
    final earnings = ref.watch(courierEarningsProvider).value;
    final chosen = switch (_span) {
      _Span.today => earnings?.today,
      _Span.week => earnings?.week,
      _Span.month => earnings?.month,
    };

    // Nothing at all to say: no work today and nothing over the month either. A card of
    // zeros on a rider's first morning reads as a broken screen.
    if ((summary == null || summary.isEmpty) &&
        (chosen == null || chosen.isEmpty)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: CourierScreen.summaryKey,
      margin: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.xs,
      ),
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
          Text('شغلك', style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.sm),
          // Three spans on one screen rather than a screen of their own: courier mode is
          // deliberately one page somebody can read at a junction, and this is a
          // modification of the card that was already here.
          SegmentedButton<_Span>(
            segments: [
              ButtonSegment(
                value: _Span.today,
                label: Text('النهاردة', key: CourierScreen.spanKey('today')),
              ),
              ButtonSegment(
                value: _Span.week,
                label: Text('الأسبوع', key: CourierScreen.spanKey('week')),
              ),
              ButtonSegment(
                value: _Span.month,
                label: Text('الشهر', key: CourierScreen.spanKey('month')),
              ),
            ],
            selected: {_span},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _span = s.first),
          ),
          const SizedBox(height: Space.sm),
          LuqmaBillLine(
            key: CourierScreen.summaryDeliveredKey,
            label: 'اتسلّم',
            value: strings.orderCount(chosen?.delivered ?? summary?.delivered ?? 0),
          ),
          const SizedBox(height: Space.xs),
          LuqmaBillLine(
            key: CourierScreen.summaryReturnedKey,
            label: 'اترجع',
            value: strings.orderCount(chosen?.returned ?? summary?.returned ?? 0),
          ),
          const SizedBox(height: Space.xs),
          LuqmaBillLine(
            key: CourierScreen.summaryCashKey,
            // Only today's cash is in a pocket. Last month's was handed over weeks ago,
            // and calling it «كاش في إيدك» would have a rider counting money they spent.
            label: _span == _Span.today ? 'كاش في إيدك' : 'حصّلت',
            value: strings.price(chosen?.cash ?? summary?.cash ?? 0),
          ),
          if (chosen != null && chosen.commission > 0) ...[
            const SizedBox(height: Space.xs),
            LuqmaBillLine(
              key: CourierScreen.summaryCommissionKey,
              label: 'عمولة لقمة',
              value: strings.price(chosen.commission),
            ),
          ],
          if (chosen != null && (chosen.fees > 0 || chosen.delivered > 0)) ...[
            const SizedBox(height: Space.xs),
            LuqmaBillLine(
              key: CourierScreen.summaryNetKey,
              label: 'ليك',
              value: strings.price(chosen.net),
              emphasis: true,
            ),
          ],
          const SizedBox(height: Space.sm),
          // The way out of the one-screen mode, and the answer to «عليّ قد إيه وهل اتسدد».
          // The delivery page stays as small as it was; this is a page of its own.
          OutlinedButton.icon(
            key: CourierScreen.statementKey,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CourierStatementScreen(),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: Sizes.iconSm),
            label: const Text('كشف الحساب'),
          ),
          // The per-shop split is what settles a shift, so it belongs to today and to
          // nothing else: a month of shops is a page, not a line somebody reads standing up.
          if (_span == _Span.today && summary != null && summary.shops.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Divider(color: colors.hairline, height: 1),
            const SizedBox(height: Space.xs),
            for (final shop in summary.shops)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: LuqmaBillLine(
                  key: CourierScreen.summaryShopKey(shop.merchantId),
                  label:
                      '${shop.merchantName} (${shop.delivered} تسليم${shop.returned > 0 ? ' · ${shop.returned} رجوع' : ''})',
                  value: strings.price(shop.cash),
                ),
              ),
          ],
        ],
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

/// Whose money is in the rider's hand, under the figure they are collecting.
///
/// A rider holding 120 ج has three questions and the order answers all three. The split
/// is computed by [CourierCut] from the same numbers `apply_courier_settlement` uses, so
/// what this shows at the door is what the server records a moment later.
class _CutBreakdown extends ConsumerWidget {
  const _CutBreakdown({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    // The roster row with no shop is what the server asks before charging anything. Not
    // known yet reads as not on it: showing a shop's rider a commission for a moment is
    // the wrong way to be wrong, and the card redraws once the roster arrives.
    final carried = ref.watch(carriedMerchantsProvider).value ?? const [];
    final cut = CourierCut.of(
      order,
      onPlatformRoster: carried.contains(null),
      commissionPercent: ref.watch(appConfigProvider).courierCommissionPercent,
    );

    // The shop's own rider: everything goes back to the shop, and what they are paid for
    // the trip is between them. The app has no column for that and says so rather than
    // printing a number it would be guessing at.
    if (cut.shopSettles) {
      return Padding(
        key: CourierScreen.cutKey(order.id),
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
        child: Text(
          'كل الفلوس دي للمحل. حسابك على التوصيلة بينك وبين المحل.',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      );
    }

    return Padding(
      key: CourierScreen.cutKey(order.id),
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LuqmaBillLine(label: 'تدي المحل', value: strings.price(cut.forShop)),
          const SizedBox(height: Space.xs),
          LuqmaBillLine(label: 'ليك', value: strings.price(cut.forCourier)),
          if (cut.forPlatform > 0) ...[
            const SizedBox(height: Space.xs),
            LuqmaBillLine(
              label: 'عمولة لقمة',
              value: strings.price(cut.forPlatform),
            ),
            const SizedBox(height: Space.xs),
            // Said plainly, because a rider who thinks this comes out of the cash in
            // their hand will hand over the wrong money at the door.
            Text(
              'العمولة مش بتتخصم دلوقتي — بتتحسب عليك وبتتحصّل كاش آخر الأسبوع.',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
