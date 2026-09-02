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
}) async {
  // Phase 0 containment. Approval currently changes a database status but no delivery
  // pipeline queues the paid notification, so offering the channel would sell silence.
  // Kept as a form option, disabled and explained, so re-enabling it later is explicit.
  const pushOpen = false;
  if (!context.mounted) return;

  final promotion = await showModalBottomSheet<Promotion>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RequestForm(
      existing: existing,
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
    required this.merchantId,
    required this.requestedBy,
    required this.cityId,
    required this.now,
    required this.pushOpen,
  });

  /// The placement being corrected, or null when asking for a new one.
  final Promotion? existing;

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
                              'الإرسال متوقف مؤقتًا لحد ما يكتمل نظام التوصيل.',
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
                          height: 120,
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
