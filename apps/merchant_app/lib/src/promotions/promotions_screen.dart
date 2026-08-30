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
  static const pushFullKey = Key('promo.pushFull');

  static Key cardKey(String id) => Key('promo.card.$id');
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantId = ref.watch(staffIdentityProvider).merchantId;
    final colors = Theme.of(context).luqma;

    if (merchantId == null) return const SizedBox.shrink();

    final mine = ref.watch(merchantPromotionsProvider(merchantId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('الإعلانات')),
      body: LuqmaAsyncView(
        value: mine,
        errorKey: MerchantPromotionsScreen.errorKey,
        onRetry: () => ref.invalidate(merchantPromotionsProvider(merchantId)),
        empty: LuqmaEmptyView(
            key: MerchantPromotionsScreen.emptyKey,
            icon: Icons.campaign_outlined,
            title: 'لسه مطلبتش إعلان',
          ),
        isEmpty: (value) => value.isEmpty,
        builder: (context, value) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.gutter,
              Space.gutter,
              Space.xxxl * 2,
            ),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.md),
            itemBuilder: (context, i) => _Card(promotion: value[i]),
          )
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: askKey,
        onPressed: () => _ask(context, ref, merchantId),
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('اطلب إعلان'),
      ),
    );
  }

  Future<void> _ask(
    BuildContext context,
    WidgetRef ref,
    String merchantId,
  ) async {
    // `.future` rethrows, and this is a tap handler: a dropped connection threw an
    // unhandled async error, the sheet never opened, and the merchant got no word at
    // all — the FAB simply stopped working.
    //
    // Unknown closes the slot rather than opening it, which is the same call
    // `pushSlotAvailableProvider` already makes for an unreadable count: one push too
    // many costs a city's notifications for good, and the other three channels are
    // still there to ask for.
    bool pushOpen;
    try {
      pushOpen = await ref.read(pushSlotAvailableProvider.future);
    } on Object {
      pushOpen = false;
    }
    if (!context.mounted) return;

    final promotion = await showModalBottomSheet<Promotion>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RequestForm(
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

    final result = await ref.read(promotionRepositoryProvider).request(promotion);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          switch (result) {
            Ok() => 'وصل طلبك. هنراجعه ونرد عليك.',
            Err() => 'مقدرناش نبعت الطلب. جرّب تاني.',
          },
        ),
      ),
    );
  }
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
                style: LuqmaType.bodySmall
                    .copyWith(color: tone, fontWeight: FontWeight.w600),
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
            style: LuqmaType.caption.copyWith(color: colors.textSecondary),
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
        ],
      ),
    );
  }

  static String _day(DateTime date) => '${date.day}/${date.month}';
}

class _RequestForm extends ConsumerStatefulWidget {
  const _RequestForm({
    required this.merchantId,
    required this.requestedBy,
    required this.cityId,
    required this.now,
    required this.pushOpen,
  });

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
  final _title = TextEditingController();
  final _body = TextEditingController();

  PromotionChannel? _channel;

  /// The banner's picture, if the merchant supplied one.
  ///
  /// Optional: a text banner on the burgundy gradient is a real render mode and the
  /// cheapest thing to ask for. What the schema refuses is the middle case — a banner
  /// that claims a picture and carries none renders as a broken box on the home screen
  /// of every customer in the city — so the render mode is derived from this rather than
  /// picked separately.
  String? _mediaId;
  String? _mediaUrl;

  /// A boost has nothing to write: no headline is ever shown for one. Asking for text
  /// would be asking for something nobody will ever read.
  bool get _needsText => _channel != null && _channel != PromotionChannel.boost;

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
    if (_needsText && title.isEmpty) return;

    Navigator.of(context).pop(
      Promotion(
        id: '',
        cityId: widget.cityId,
        merchantId: widget.merchantId,
        channel: channel,
        // Derived, never chosen: `promotions_image_has_media` refuses a row whose mode
        // promises a picture it does not have, so the mode follows the picture.
        renderMode: _mediaId == null
            ? PromotionRender.text
            : (title.isEmpty ? PromotionRender.image : PromotionRender.imageWithText),
        mediaId: _mediaId,
        title: title,
        body: _body.text.trim(),
        // A week from tomorrow, which is what a merchant asking today means. The admin
        // moves it when they approve; a date picker for the common case is a step.
        startAt: widget.now.add(const Duration(days: 1)),
        endAt: widget.now.add(const Duration(days: 8)),
        requestedBy: widget.requestedBy,
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
              Text('اطلب إعلان', style: theme.textTheme.titleLarge),
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
                              channel == PromotionChannel.push && !widget.pushOpen
                                  ? null
                                  : () => setState(() => _channel = channel),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                            backgroundColor:
                                _channel == channel ? colors.surface : null,
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
                                style: LuqmaType.caption
                                    .copyWith(color: colors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (channel == PromotionChannel.push && !widget.pushOpen)
                          Padding(
                            key: MerchantPromotionsScreen.pushFullKey,
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Text(
                              // With a horizon. "No" with no end date reads as
                              // permanent, and a merchant told that stops asking.
                              'خلصت إشعارات الأسبوع ده. جرّب الأسبوع الجاي.',
                              style: LuqmaType.bodySmall
                                  .copyWith(color: colors.textSecondary),
                            ),
                          ),
                        const SizedBox(height: Sizes.targetGap),
                      ],
                      if (_needsText) ...[
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
                      ],
                      // A boost has no banner to carry a picture on.
                      if (_needsText) ...[
                        const SizedBox(height: Space.md),
                        MediaPicker(
                          kind: MediaKind.promotion,
                          url: _mediaUrl,
                          name: _title.text.trim().isEmpty
                              ? 'إعلان'
                              : _title.text.trim(),
                          ownerId: widget.merchantId,
                          height: 120,
                          onUploaded: (media) => setState(() {
                            _mediaId = media.id;
                            _mediaUrl = media.url;
                          }),
                        ),
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
                child: const Text('ابعت الطلب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


