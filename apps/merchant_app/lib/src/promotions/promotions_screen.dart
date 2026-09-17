import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// Asking to be seen.
///
/// One screen and one flow for all four channels, because to a merchant they are one
/// thing: paying for attention. What differs between them is what the form asks for, not
/// four separate journeys.
///
/// Nothing here goes live. A merchant asks and an admin decides — that asymmetry is what
/// keeps a 50%-off headline nobody checked off every customer's home screen, and
/// unmoderated push off their notification tray.
class MerchantPromotionsScreen extends ConsumerWidget {
  const MerchantPromotionsScreen({super.key});

  static const emptyKey = Key('promo.empty');
  static const errorKey = Key('promo.error');
  static const askKey = Key('promo.ask');
  static const titleKey = Key('promo.title');
  static const bodyKey = Key('promo.body');
  static const submitKey = Key('promo.submit');
  static const pushUnavailableKey = Key('promo.pushUnavailable');
  static const modeKey = Key('promo.mode');
  static const showAllKey = Key('promo.showAll');

  static Key cardKey(String id) => Key('promo.card.$id');
  static Key editKey(String id) => Key('promo.edit.$id');
  static Key scheduledKey(String id) => Key('promo.scheduled.$id');
  static Key channelKey(PromotionChannel channel) =>
      Key('promo.channel.${channel.name}');

  static const channelNames = {
    PromotionChannel.homeBanner: 'بانر في الرئيسية',
    PromotionChannel.categoryBanner: 'بانر في قسم',
    PromotionChannel.boost: 'رفع في ترتيب المطاعم',
    PromotionChannel.push: 'إشعار للعملاء',
  };

  static const channelNotes = {
    PromotionChannel.homeBanner: 'بانر بيظهر لكل اللي بيفتحوا التطبيق.',
    PromotionChannel.categoryBanner: 'بانر جوه قسم معيّن.',
    PromotionChannel.boost: 'مطعمك بيطلع فوق في القوايم. مفيش كلام ولا صورة.',
    PromotionChannel.push: 'إشعار بيوصل موبايل العميل حتى لو التطبيق مقفول.',
  };

  /// The campaign list only grows over time, so showing every campaign ever requested
  /// overwhelms the merchant. Order by relevance so what matters right now comes first:
  /// 1. Live now: currently in front of customers.
  /// 2. Upcoming approved: signed off and scheduled to run soon.
  /// 3. Requested: waiting for admin review.
  /// 4. Rejected: needs correction or a replacement request.
  /// 5. Ended: finished history.
  /// Within the same rank, newer start date first.
  static int relevanceRank(Promotion p, DateTime now) {
    if (p.isLiveAt(now)) return 0;
    if ((p.status == PromotionStatus.approved ||
            p.status == PromotionStatus.active) &&
        p.startAt.isAfter(now)) {
      return 1;
    }
    if (p.status == PromotionStatus.requested) return 2;
    if (p.status == PromotionStatus.rejected) return 3;
    return 4;
  }

  static int compareByRelevance(Promotion a, Promotion b, DateTime now) {
    final rankA = relevanceRank(a, now);
    final rankB = relevanceRank(b, now);
    if (rankA != rankB) return rankA.compareTo(rankB);
    final start = b.startAt.compareTo(a.startAt);
    if (start != 0) return start;
    return b.id.compareTo(a.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantId = ref.watch(staffIdentityProvider).merchantId;
    final theme = Theme.of(context);
    final colors = theme.luqma;

    if (merchantId == null) return const SizedBox.shrink();

    final mine = ref.watch(merchantPromotionsProvider(merchantId));
    final merchant = switch (ref.watch(merchantProvider(merchantId))) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final subscription = switch (ref.watch(subscriptionProvider(merchantId))) {
      AsyncData(:final value) => value,
      _ => null,
    };
    final plans = switch (ref.watch(plansProvider)) {
      AsyncData(:final value) => value,
      _ => const <Plan>[],
    };
    final plan = plans.where((p) => p.id == merchant?.planId).firstOrNull;
    final pushOpen = ref.watch(pushSlotAvailableProvider).value ?? false;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('الخطة والعروض')),
      body: LuqmaAsyncView(
        value: mine,
        errorKey: MerchantPromotionsScreen.errorKey,
        onRetry: () => ref.invalidate(merchantPromotionsProvider(merchantId)),
        builder: (context, value) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.gutter,
            Space.gutter,
            Space.xxxl * 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PlanCard(
                merchant: merchant,
                subscription: subscription,
                plan: plan,
                now: ref.watch(clockProvider)(),
              ),
              const SizedBox(height: Space.md),
              _Allowance(merchantId: merchantId),
              const SizedBox(height: Space.section),
              if (value.isNotEmpty) ...[
                _CampaignsSection(promotions: value),
              ],
              _RequestTypes(
                merchantId: merchantId,
                pushOpen: pushOpen,
              ),
              if (value.isEmpty) ...[
                const SizedBox(height: Space.md),
                const LuqmaEmptyView(
                  key: MerchantPromotionsScreen.emptyKey,
                  icon: Icons.campaign_outlined,
                  title: 'لسه مطلبتش إعلان',
                ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: askKey,
        onPressed: () => _ask(context, ref, merchantId),
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('اطلب إعلان'),
      ),
    );
  }
}

class _CampaignsSection extends ConsumerStatefulWidget {
  const _CampaignsSection({required this.promotions});

  final List<Promotion> promotions;

  @override
  ConsumerState<_CampaignsSection> createState() => _CampaignsSectionState();
}

class _CampaignsSectionState extends ConsumerState<_CampaignsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();

    final sorted = List<Promotion>.from(widget.promotions)
      ..sort((a, b) => MerchantPromotionsScreen.compareByRelevance(a, b, now));

    final hasMore = sorted.length > 3;
    final visible = (_expanded || !hasMore) ? sorted : sorted.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'طلباتك وحملاتك',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: Space.sm),
        for (final promo in visible) ...[
          _Card(promotion: promo),
          const SizedBox(height: Space.md),
        ],
        if (hasMore) ...[
          Center(
            child: TextButton(
              key: MerchantPromotionsScreen.showAllKey,
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'عرض أقل' : 'عرض الكل'),
            ),
          ),
          const SizedBox(height: Space.sm),
        ] else
          const SizedBox(height: Space.sm),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.merchant,
    required this.subscription,
    required this.plan,
    required this.now,
  });

  final DateTime now;
  final Merchant? merchant;
  final Subscription? subscription;
  final Plan? plan;

  static String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final planName =
        plan?.name ??
        switch (merchant?.revenueModel) {
          RevenueModel.prepaid => 'رصيد مسبق الدفع',
          RevenueModel.commission => 'عمولة على الطلبات',
          RevenueModel.subscription => 'اشتراك',
          null => 'بيانات الخطة غير متاحة',
        };

    final renewalText = subscription != null
        ? 'ينتهي في ${_formatDate(subscription!.expiresAt)}'
        : merchant?.revenueModel == RevenueModel.prepaid
        ? 'رصيد مسبق الدفع للطلبات'
        : null;

    // The term that is running now — not merely the latest one, which stays readable after it
    // ends until the nightly pass clears the plan.
    final planActive = merchant?.planId != null &&
        subscription != null &&
        subscription!.expiresAt.isAfter(now);

    final commissionRate = !planActive &&
            merchant != null &&
            merchant!.revenueModel == RevenueModel.commission
        ? '${(merchant!.revenueValue / 100).toStringAsFixed(2)}%'
        : null;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [LuqmaPalette.burgundy, LuqmaPalette.burgundyDark],
        ),
        borderRadius: Radii.cardAll,
        boxShadow: Elevations.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            bottom: -20,
            left: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent.withValues(alpha: 0.20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الخطة الحالية',
                  style: LuqmaType.caption.copyWith(
                    color: colors.onBrand.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  planName,
                  style: LuqmaType.sectionTitle.copyWith(
                    color: colors.onBrand,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (renewalText != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    renewalText,
                    style: LuqmaType.bodySmall.copyWith(
                      color: colors.onBrand.withValues(alpha: 0.90),
                    ),
                  ),
                ],
                const SizedBox(height: Space.md),
                Wrap(
                  spacing: Space.md,
                  runSpacing: Space.xs,
                  children: [
                    // Only what a plan actually does. The item limit and "detailed
                    // statistics" were shown here and enforced nowhere — every shop has
                    // the statistics, and no menu is capped.
                    if (planActive)
                      _FeaturePill(
                        text: '✓ مفيش عمولة على الطلبات',
                        color: colors.onBrand,
                      ),
                    if (commissionRate != null)
                      _FeaturePill(
                        text: '✓ نسبة عمولة $commissionRate',
                        color: colors.onBrand,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: Radii.pillAll,
      ),
      child: Text(
        text,
        style: LuqmaType.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RequestTypes extends ConsumerWidget {
  const _RequestTypes({required this.merchantId, required this.pushOpen});

  final String merchantId;
  final bool pushOpen;

  static const homeBannerCardKey = Key('promo.type.homeBanner');
  static const boostCardKey = Key('promo.type.boost');
  static const pushCardKey = Key('promo.type.push');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final cards = [
      (
        key: homeBannerCardKey,
        icon: Icons.campaign_rounded,
        title: 'بانر إعلاني',
        desc: 'اظهر في الصفحة الرئيسية',
        price: '150 ج / أسبوع',
        channel: PromotionChannel.homeBanner,
        enabled: true,
      ),
      (
        key: boostCardKey,
        icon: Icons.star_rounded,
        title: 'رفع الترتيب',
        desc: 'يظهر محلك في الأول',
        price: '80 ج / أسبوع',
        channel: PromotionChannel.boost,
        enabled: true,
      ),
      (
        key: pushCardKey,
        icon: Icons.notifications_active_rounded,
        title: 'إشعار جماعي',
        desc: 'يوصل لكل عملاء إدكو',
        price: '250 ج / مرة',
        channel: PromotionChannel.push,
        enabled: pushOpen,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اطلب عرض ترويجي',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: Space.sm),
        for (final item in cards) ...[
          Container(
            padding: const EdgeInsets.all(Space.md),
            margin: const EdgeInsets.only(bottom: Space.sm),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: Radii.cardAll,
              border: Border.all(color: colors.hairline),
              boxShadow: Elevations.card,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    item.icon,
                    size: Sizes.iconMd,
                    color: colors.brand,
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: LuqmaType.bodyStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.desc,
                        style: LuqmaType.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.price,
                      style: LuqmaType.caption.copyWith(
                        color: colors.price,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    FilledButton(
                      key: item.key,
                      onPressed: item.enabled
                          ? () => _ask(
                              context,
                              ref,
                              merchantId,
                              initialChannel: item.channel,
                            )
                          : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                          vertical: Space.xs,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('اطلب'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Asking for a placement, or correcting one already asked for.
///
/// One form for both, because to a merchant they are one thing — what this banner
/// says. The only difference is where it lands, and that is [existing]: null asks for
/// something new, and anything else is a correction that goes back to the queue.
Future<void> _ask(
  BuildContext context,
  WidgetRef ref,
  String merchantId, {
  Promotion? existing,
  PromotionChannel? initialChannel,
}) async {
  // If the availability check is still loading, or if it fails, treat the slot as
  // unavailable rather than open.
  final pushOpen = ref.read(pushSlotAvailableProvider).value ?? false;
  if (!context.mounted) return;

  final promotion = await showModalBottomSheet<Promotion>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RequestForm(
      existing: existing,
      initialChannel: initialChannel,
      merchantId: merchantId,
      // The person, not the shop. `requested_by` references `auth.users`, and a
      // merchant id is a row in `merchants` — sending it meant every request a
      // merchant made was refused by the foreign key.
      requestedBy: ref.read(currentIdentityProvider).value?.uid ?? '',
      cityId: ref.read(currentCityProvider),
      now: ref.read(clockProvider)(),
      pushOpen: pushOpen,
    ),
  );

  if (promotion == null || !context.mounted) return;

  final repository = ref.read(promotionRepositoryProvider);
  final result = existing == null
      ? await repository.request(promotion)
      : await repository.editRequest(promotion);
  if (!context.mounted) return;

  // What the plan still covers has just changed — the server decides it at the insert, so
  // the card must ask again rather than keep promising the slot it has already spent.
  ref.invalidate(planAllowanceProvider(merchantId));

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(switch (result) {
        // An edit is a fresh ask, and saying so is what stops a merchant expecting
        // their correction to be live already.
        Ok() when existing != null => 'التعديل وصل. هنراجعه تاني ونرد عليك.',
        Ok() => 'وصل طلبك. هنراجعه ونرد عليك.',
        Err(:final failure) => switch (failure) {
          OfflineFailure() => 'مفيش نت — جرّب تاني.',
          PermissionFailure() => 'الإعلان ده بدأ خلاص، مش هينفع يتعدّل.',
          _ => 'مقدرناش نبعت الطلب. جرّب تاني.',
        },
      }),
    ),
  );
}

class _Card extends ConsumerWidget {
  const _Card({required this.promotion});

  final Promotion promotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final now = ref.watch(clockProvider)();

    // Whether it is running is a question about the calendar, not about which of two
    // words the status holds. Nothing on the server ever writes `active` — `approve()`
    // writes `approved` and `startAt` decides the rest — so a label keyed on the status
    // alone told a merchant whose banner was live that it had merely been signed off.
    final (tone, label) = switch (promotion.status) {
      PromotionStatus.requested => (colors.textSecondary, 'تحت المراجعة'),
      PromotionStatus.approved || PromotionStatus.active =>
        promotion.isLiveAt(now)
            ? (colors.success, 'شغال دلوقتي')
            : (colors.success, 'اتوافق عليه'),
      PromotionStatus.rejected => (colors.danger, 'مرفوض'),
      PromotionStatus.ended => (colors.textSecondary, 'خلص'),
    };

    return Container(
      key: MerchantPromotionsScreen.cardKey(promotion.id),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  MerchantPromotionsScreen.channelNames[promotion.channel]!,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                label,
                style: LuqmaType.bodySmall.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (promotion.title.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(promotion.title, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: Space.xs),
          Text(
            'من ${_day(promotion.startAt)} لـ ${_day(promotion.endAt)}',
            style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
          ),
          // Approved is not live. Without this, a merchant whose campaign starts on
          // Tuesday opens the app on Monday and thinks something is broken.
          // `now`, read from `clockProvider` above — not the wall clock. Two reads of
          // two different clocks let the status chip and this hint disagree, and made
          // the test that covers it pass only while the real date sits before `startAt`.
          if (promotion.status == PromotionStatus.approved &&
              !promotion.isLiveAt(now)) ...[
            const SizedBox(height: Space.xs),
            Text(
              'هيبدأ ${_day(promotion.startAt)}',
              key: MerchantPromotionsScreen.scheduledKey(promotion.id),
              style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ],
          // The whole reason a refusal costs a sentence: something to fix, rather than
          // the same request sent again next week.
          if (promotion.rejectionReason != null) ...[
            const SizedBox(height: Space.sm),
            Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.08),
                borderRadius: Radii.cardAll,
              ),
              child: Text(
                promotion.rejectionReason!,
                style: LuqmaType.bodySmall.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
          // Only while it is still theirs to change. `isEditableAt` is the same pair of
          // conditions the policy holds, so this button is never offered for something
          // the database would refuse — a merchant told "no" by a policy has no way to
          // tell that from the app being broken.
          if (promotion.isEditableAt(now)) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: MerchantPromotionsScreen.editKey(promotion.id),
                onPressed: () => _ask(
                  context,
                  ref,
                  promotion.merchantId,
                  existing: promotion,
                ),
                icon: const Icon(Icons.edit_outlined, size: Sizes.iconSm),
                label: const Text('عدّل'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _day(DateTime date) => '${date.day}/${date.month}';
}

class _RequestForm extends ConsumerStatefulWidget {
  const _RequestForm({
    this.existing,
    this.initialChannel,
    required this.merchantId,
    required this.requestedBy,
    required this.cityId,
    required this.now,
    required this.pushOpen,
  });

  /// The placement being corrected, or null when asking for a new one.
  final Promotion? existing;

  /// The channel pre-selected when opened from a request type card.
  final PromotionChannel? initialChannel;

  final String merchantId;

  /// The signed-in owner's uid. `requested_by` references `auth.users`, so this is a
  /// person and never the shop — those are two different uuids and only one of them is
  /// a row the foreign key can find.
  final String requestedBy;

  final String cityId;
  final DateTime now;

  /// Whether the city has a marketing push left this week.
  final bool pushOpen;

  @override
  ConsumerState<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends ConsumerState<_RequestForm> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _body = TextEditingController(text: widget.existing?.body ?? '');

  PromotionChannel? _channel;

  /// The banner's picture, when the merchant chose a picture banner.
  ///
  /// A banner is one thing or the other. `imageWithText` used to lay the headline over
  /// the artwork, and it is the one mode nobody can design for: the photograph decides
  /// where its own dark parts are, so white text is legible on the picture it was tested
  /// against and gone on the next one.
  String? _mediaId;
  String? _mediaUrl;

  /// The ground the words sit on. Null is the brand gradient.
  String? _backgroundColor;

  /// Which of the two this banner is.
  bool _picture = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      // A correction opens on what was asked for. Making the merchant re-pick the
      // channel and re-upload the picture to fix a headline is how an edit affordance
      // ends up unused.
      _channel = existing.channel;
      _mediaId = existing.mediaId;
      _mediaUrl = existing.imageUrl;
      _backgroundColor = existing.backgroundColor;
      _picture = existing.renderMode == PromotionRender.image;
    } else if (widget.initialChannel != null) {
      _channel = widget.initialChannel;
    }
  }

  /// A boost has nothing to show: no headline and no artwork is ever drawn for one, so
  /// neither half of the choice applies.
  bool get _isBanner => _channel != null && _channel != PromotionChannel.boost;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    final channel = _channel;
    if (channel == null) return;

    final title = _title.text.trim();
    // Each mode has one thing it cannot be sent without, and it is not the same thing.
    if (_isBanner && _picture && _mediaId == null) return;
    if (_isBanner && !_picture && title.isEmpty) return;

    Navigator.of(context).pop(
      Promotion(
        // A correction keeps its id — that is what makes it the same placement rather
        // than a second one in the queue beside the first.
        id: widget.existing?.id ?? '',
        cityId: widget.cityId,
        merchantId: widget.merchantId,
        channel: channel,
        renderMode: _isBanner && _picture
            ? PromotionRender.image
            : PromotionRender.text,
        // Only what the chosen mode actually draws is carried. A text banner keeping a
        // media id is a picture the merchant thinks they are still paying for.
        mediaId: _isBanner && _picture ? _mediaId : null,
        backgroundColor: _isBanner && !_picture ? _backgroundColor : null,
        title: _picture && _isBanner ? '' : title,
        body: _picture && _isBanner ? '' : _body.text.trim(),
        // A correction leaves the window alone. The dates are the admin's — they are
        // what decides when it appears — and resetting them to "a week from now" every
        // time somebody fixed a typo would quietly undo the admin's scheduling.
        startAt: widget.existing?.startAt ?? widget.now,
        endAt:
            widget.existing?.endAt ?? widget.now.add(const Duration(days: 7)),
        requestedBy: widget.existing?.requestedBy ?? widget.requestedBy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? 'اطلب إعلان' : 'عدّل الإعلان',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Space.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final channel in PromotionChannel.values) ...[
                        OutlinedButton(
                          key: MerchantPromotionsScreen.channelKey(channel),
                          onPressed:
                              channel == PromotionChannel.push &&
                                  !widget.pushOpen
                              ? null
                              : () => setState(() => _channel = channel),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor: _channel == channel
                                ? colors.surface
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                MerchantPromotionsScreen.channelNames[channel]!,
                                style: LuqmaType.button,
                              ),
                              Text(
                                MerchantPromotionsScreen.channelNotes[channel]!,
                                style: LuqmaType.caption.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (channel == PromotionChannel.push &&
                            !widget.pushOpen)
                          Padding(
                            key: MerchantPromotionsScreen.pushUnavailableKey,
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Text(
                              'اكتمل الحد الأسبوعي للإشعارات في المدينة.',
                              style: LuqmaType.bodySmall.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        const SizedBox(height: Sizes.targetGap),
                      ],
                      // Picture or words, and it is a choice rather than something
                      // inferred from what the merchant happened to fill in. Deriving it
                      // meant somebody who uploaded artwork *and* typed a headline got
                      // both, laid on top of each other, without ever asking for that.
                      if (_isBanner) ...[
                        const SizedBox(height: Space.md),
                        SegmentedButton<bool>(
                          key: MerchantPromotionsScreen.modeKey,
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('كلام'),
                              icon: Icon(Icons.title_outlined),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('صورة'),
                              icon: Icon(Icons.image_outlined),
                            ),
                          ],
                          selected: {_picture},
                          onSelectionChanged: (picked) =>
                              setState(() => _picture = picked.first),
                        ),
                      ],
                      if (_isBanner && !_picture) ...[
                        const SizedBox(height: Space.sm),
                        TextField(
                          key: MerchantPromotionsScreen.titleKey,
                          controller: _title,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            labelText: 'العنوان',
                            hintText: 'خصم ١٥٪ على المشويات',
                          ),
                        ),
                        TextField(
                          key: MerchantPromotionsScreen.bodyKey,
                          controller: _body,
                          maxLength: 70,
                          decoration: const InputDecoration(
                            labelText: 'سطر تاني (اختياري)',
                          ),
                        ),
                        const SizedBox(height: Space.md),
                        Text(
                          'لون الخلفية',
                          style: LuqmaType.button.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        BannerColorPicker(
                          selected: _backgroundColor,
                          onPicked: (hex) =>
                              setState(() => _backgroundColor = hex),
                        ),
                      ],
                      if (_isBanner && _picture) ...[
                        const SizedBox(height: Space.md),
                        MediaPicker(
                          kind: MediaKind.promotion,
                          url: _mediaUrl,
                          name: 'إعلان',
                          ownerId: widget.merchantId,
                          onUploaded: (media) => setState(() {
                            _mediaId = media.id;
                            _mediaUrl = media.url;
                          }),
                        ),
                        // The one thing a picture banner cannot be sent without, said
                        // before the button refuses rather than after.
                        if (_mediaId == null) ...[
                          const SizedBox(height: Space.xs),
                          Text(
                            'اختار صورة الإعلان.',
                            style: LuqmaType.bodySmall.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
              FilledButton(
                key: MerchantPromotionsScreen.submitKey,
                onPressed: _channel == null ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(
                  widget.existing == null ? 'ابعت الطلب' : 'ابعت التعديل',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What this month's plan still covers.
///
/// A plan can include a number of banners and marketing notifications a month (2026-09-17).
/// The server decides whether a request lands inside that number — this says what is left so
/// the shop knows before it asks whether it is about to agree a price.
class _Allowance extends ConsumerWidget {
  const _Allowance({required this.merchantId});

  final String merchantId;

  static const allowanceKey = Key('promo.allowance');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final allowance = ref.watch(planAllowanceProvider(merchantId)).value;
    if (allowance == null || !allowance.planActive) return const SizedBox.shrink();
    if (allowance.bannersIncluded == 0 && allowance.pushesIncluded == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      key: allowanceKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('باقتك الشهر ده', style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          Text(
            [
              if (allowance.bannersIncluded > 0)
                'بانرات: ${allowance.bannersLeft} من ${allowance.bannersIncluded}',
              if (allowance.pushesIncluded > 0)
                'إشعارات: ${allowance.pushesLeft} من ${allowance.pushesIncluded}',
            ].join(' · '),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Space.xs),
          Text(
            'اللي زيادة عن كده بتتفق عليه مع الإدارة.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
