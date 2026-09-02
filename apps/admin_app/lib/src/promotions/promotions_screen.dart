import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../merchants/merchants_controller.dart';
import '../shell/layout.dart';

/// Where a merchant's request becomes a placement, or does not.
///
/// The one asymmetry the whole promotions design rests on: a merchant may ask, and only
/// an admin may approve. Letting a merchant publish their own push is the fastest way to
/// make customers disable notifications — and every operational alert goes with it.
class PromotionsScreen extends ConsumerWidget {
  const PromotionsScreen({super.key});

  static const emptyKey = Key('promotions.empty');
  static const errorKey = Key('promotions.error');
  static const reasonKey = Key('promotions.reason');
  static const confirmRejectKey = Key('promotions.confirmReject');
  static const startNowKey = Key('promotions.startNow');
  static const keepDateKey = Key('promotions.keepDate');

  static const tabQueueKey = Key('promotions.tab.queue');
  static const tabAllKey = Key('promotions.tab.all');
  static const boardEmptyKey = Key('promotions.board.empty');
  static const boardErrorKey = Key('promotions.board.error');
  static const startFieldKey = Key('promotions.dates.start');
  static const endFieldKey = Key('promotions.dates.end');
  static const saveDatesKey = Key('promotions.dates.save');

  static Key datesKey(String id) => Key('promotions.dates.$id');

  static const createKey = Key('promotions.create');
  static const formMerchantKey = Key('promotions.form.merchant');
  static const formChannelKey = Key('promotions.form.channel');
  static const formTitleKey = Key('promotions.form.title');
  static const formBodyKey = Key('promotions.form.body');
  static const formSubmitKey = Key('promotions.form.submit');

  static Key cardKey(String id) => Key('promotions.card.$id');
  static Key approveKey(String id) => Key('promotions.approve.$id');
  static Key rejectKey(String id) => Key('promotions.reject.$id');
  static Key pushWarningKey(String id) => Key('promotions.push.$id');

  static const channelNames = {
    PromotionChannel.homeBanner: 'بانر في الرئيسية',
    PromotionChannel.categoryBanner: 'بانر في قسم',
    PromotionChannel.boost: 'رفع في الترتيب',
    PromotionChannel.push: 'إشعار للعملاء',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    // Watched, not read at the moment of a decision: every approval is stamped with who
    // made it, so the session has to be live before any of this runs.
    ref.watch(currentIdentityProvider);

    // Two questions, not one. The queue is what needs a decision today; the board is
    // what exists — and the board is the half that was missing, so an approved campaign
    // scheduled for next week vanished from the admin's view the moment they signed it
    // off, with no way back to it and no way to move its dates.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('الإعلانات'),
          actions: [
            IconButton(
              key: createKey,
              tooltip: 'إعلان جديد',
              icon: const Icon(Icons.add),
              onPressed: () => _create(context, ref),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(key: tabQueueKey, text: 'طلبات'),
              Tab(key: tabAllKey, text: 'كل الإعلانات'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            AdminContent(
              child: LuqmaAsyncView(
                value: ref.watch(promotionQueueProvider),
                errorKey: PromotionsScreen.errorKey,
                onRetry: () => ref.invalidate(promotionQueueProvider),
                empty: LuqmaEmptyView(
                  key: PromotionsScreen.emptyKey,
                  title: 'مفيش طلبات إعلانات مستنية.',
                ),
                isEmpty: (value) => value.isEmpty,
                builder: (context, value) => ListView.separated(
                  padding: const EdgeInsets.all(Space.gutter),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (context, i) => _Request(promotion: value[i]),
                ),
              ),
            ),
            AdminContent(
              child: LuqmaAsyncView(
                value: ref.watch(allPromotionsProvider),
                errorKey: PromotionsScreen.boardErrorKey,
                onRetry: () => ref.invalidate(allPromotionsProvider),
                empty: LuqmaEmptyView(
                  key: PromotionsScreen.boardEmptyKey,
                  icon: Icons.campaign_outlined,
                  title: 'مفيش إعلانات لسه.',
                ),
                isEmpty: (value) => value.isEmpty,
                builder: (context, value) => ListView.separated(
                  padding: const EdgeInsets.all(Space.gutter),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (context, i) => _Placement(promotion: value[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final draft = await showModalBottomSheet<Promotion>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateForm(),
    );
    if (draft == null || !context.mounted) return;

    // Stamped with the admin who made it, exactly as an approval is: "who put this up"
    // has to be answerable months later, and an approval nobody signed is not one.
    final by = ref.read(currentIdentityProvider).value?.uid;
    if (by == null) return;

    final made = await ref
        .read(promotionRepositoryProvider)
        .createApproved(draft, approvedBy: by);

    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (made) {
          Ok() => 'الإعلان اتحط.',
          // Silence after a tap is indistinguishable from a broken button.
          Err(:final failure) => switch (failure) {
            PermissionFailure() => 'مش مسموحلك تحط إعلانات.',
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            _ => 'معرفناش نحط الإعلان. جرّب تاني.',
          },
        }),
      ),
    );
  }
}

class _Request extends ConsumerWidget {
  const _Request({required this.promotion});

  final Promotion promotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final merchant = ref.watch(merchantProvider(promotion.merchantId)).value;

    return Container(
      key: PromotionsScreen.cardKey(promotion.id),
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
                child: Text(
                  merchant?.name ?? promotion.merchantId,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                PromotionsScreen.channelNames[promotion.channel]!,
                style: LuqmaType.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          if (promotion.channel == PromotionChannel.push) ...[
            const SizedBox(height: Space.sm),
            Container(
              key: PromotionsScreen.pushWarningKey(promotion.id),
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: Radii.cardAll,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.campaign_outlined,
                    size: Sizes.iconSm,
                    // Dark on the orange, never white: white on it is 3.03:1.
                    color: colors.onAccent,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      // The one channel that reaches somebody not looking at the app,
                      // and the one that can cost every other notification we send.
                      'الإرسال متوقف مؤقتًا. ينفع ترفض الطلب لكن ما ينفعش تعتمده.',
                      style: LuqmaType.bodySmall.copyWith(
                        color: colors.onAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.sm),
          Text(promotion.title, style: theme.textTheme.titleLarge),
          if (promotion.body.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(promotion.body, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: Space.sm),
          Text(
            'من ${_day(promotion.startAt)} لـ ${_day(promotion.endAt)}'
            '${promotion.price > 0 ? ' · ${strings.price(promotion.price)}' : ''}',
            style: LuqmaType.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: PromotionsScreen.rejectKey(promotion.id),
                  onPressed: () => _reject(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.danger,
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: const Text('رفض'),
                ),
              ),
              const SizedBox(width: Sizes.targetGap),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: PromotionsScreen.approveKey(promotion.id),
                  onPressed: promotion.channel == PromotionChannel.push
                      ? null
                      : () => _approve(context, ref),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: const Text('موافقة'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _day(DateTime date) => '${date.day}/${date.month}';

  Future<void> _approve(BuildContext context, WidgetRef ref) async {
    final by = ref.read(currentIdentityProvider).value?.uid;
    if (by == null) return;

    final now = ref.read(clockProvider)();

    // A request dated in the future is approved into that future date, and the admin
    // sees nothing happen. That is correct — `startAt` decides, and a campaign meant for
    // next week must not jump the queue — but it is also exactly what the owner hit:
    // they approved a banner and it stayed invisible with no way to move it.
    //
    // So they are asked, once, and only when it matters. A request that already starts
    // now goes straight through without a dialog.
    DateTime? startAt;
    DateTime? endAt;
    if (promotion.startAt.isAfter(now)) {
      final startNow = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('يبدأ إمتى؟'),
          content: Text(
            'الطلب ده مكتوب إنه يبدأ ${_day(promotion.startAt)}. '
            'تحب يشتغل من دلوقتي؟',
          ),
          actions: [
            TextButton(
              key: PromotionsScreen.keepDateKey,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('سيبه ${_day(promotion.startAt)}'),
            ),
            FilledButton(
              key: PromotionsScreen.startNowKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('من دلوقتي'),
            ),
          ],
        ),
      );
      if (startNow == null) return;
      if (startNow) {
        startAt = now;
        // The window keeps the length the merchant asked for rather than ending on the
        // original date, which would otherwise shorten a campaign for being approved.
        endAt = now.add(promotion.endAt.difference(promotion.startAt));
      }
    }

    await ref
        .read(promotionRepositoryProvider)
        .approve(promotion.id, approvedBy: by, startAt: startAt, endAt: endAt);
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );

    if (reason == null || !context.mounted) return;

    final by = ref.read(currentIdentityProvider).value?.uid;
    if (by == null) return;

    await ref
        .read(promotionRepositoryProvider)
        .reject(promotion.id, reason: reason, by: by);
  }
}

/// One placement on the board, with the control the admin was missing.
///
/// Deliberately not the queue card: there is nothing to approve or reject here — those
/// decisions are already taken — and repeating them would give an admin two places to
/// make the same call and two answers when they disagree. What is here is the one thing
/// only they can do: decide when it appears and when it goes away.
class _Placement extends ConsumerWidget {
  const _Placement({required this.promotion});

  final Promotion promotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final now = ref.watch(clockProvider)();
    final merchant = ref.watch(merchantProvider(promotion.merchantId)).value;

    // Approved is not live, and the board is the one screen where that distinction has
    // to be legible at a glance — it is the whole reason a scheduled banner looked to
    // the owner like a broken one.
    final (tone, label) = switch (promotion.status) {
      PromotionStatus.requested => (colors.textSecondary, 'مستني مراجعة'),
      PromotionStatus.approved || PromotionStatus.active =>
        promotion.isLiveAt(now)
            ? (colors.success, 'شغال دلوقتي')
            : (colors.textSecondary, 'هيبدأ ${_day(promotion.startAt)}'),
      PromotionStatus.rejected => (colors.danger, 'مرفوض'),
      PromotionStatus.ended => (colors.textSecondary, 'خلص'),
    };

    return Container(
      key: PromotionsScreen.cardKey(promotion.id),
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
                child: Text(
                  merchant?.name ?? promotion.merchantId,
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
          const SizedBox(height: Space.xs),
          Text(
            PromotionsScreen.channelNames[promotion.channel]!,
            style: LuqmaType.caption.copyWith(color: colors.textSecondary),
          ),
          if (promotion.title.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(promotion.title, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'من ${_day(promotion.startAt)} لـ ${_day(promotion.endAt)}',
                  style: LuqmaType.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                key: PromotionsScreen.datesKey(promotion.id),
                onPressed: () => _moveDates(context, ref),
                icon: const Icon(Icons.event_outlined, size: Sizes.iconSm),
                label: const Text('المواعيد'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _moveDates(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final window = await showModalBottomSheet<({DateTime start, DateTime end})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DatesSheet(promotion: promotion),
    );
    if (window == null) return;

    final moved = await ref
        .read(promotionRepositoryProvider)
        .reschedule(promotion.id, startAt: window.start, endAt: window.end);

    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (moved) {
          Ok() => 'المواعيد اتغيرت.',
          Err(:final failure) => switch (failure) {
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            PermissionFailure() => 'مش مسموحلك تغيّر المواعيد.',
            _ => 'معرفناش نغيّر المواعيد. جرّب تاني.',
          },
        }),
      ),
    );
  }
}

/// When it appears, and when it goes away.
///
/// Two dates rather than one range picker because they answer two questions the admin
/// asks at different moments — "put this up now" and "take this down" — and a range
/// picker turns moving one of them into a re-selection of both.
class _DatesSheet extends StatefulWidget {
  const _DatesSheet({required this.promotion});

  final Promotion promotion;

  @override
  State<_DatesSheet> createState() => _DatesSheetState();
}

class _DatesSheetState extends State<_DatesSheet> {
  late DateTime _start = widget.promotion.startAt;

  /// Normalized on the way in, not only when the admin picks a new one.
  ///
  /// The sheet talks in whole days — it says (يختفي 25/9) — so a stored end of midnight on the
  /// 25th would be labelled as the 25th while actually taking the banner down as that
  /// day began. Reading it as the end of that day is what makes the label true.
  late DateTime _end = _endOfDay(widget.promotion.endAt);

  Future<void> _pick({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      // Wide on both sides: a banner can be pulled back to today or pushed into next
      // season, and a range that refuses either is a control that only half works.
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = DateTime(picked.year, picked.month, picked.day);
        // A window that ends before it starts shows nothing, silently — the placement
        // simply never appears and there is no error anywhere to read.
        if (!_end.isAfter(_start)) _end = _endOfDay(picked);
      } else {
        _end = _endOfDay(picked);
        if (!_end.isAfter(_start)) {
          _start = DateTime(picked.year, picked.month, picked.day);
        }
      }
    });
  }

  /// The end of the chosen day rather than its beginning: "until the 25th" means through
  /// the 25th, and midnight would take the banner down as that day started.
  static DateTime _endOfDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, 23, 59, 59);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('مواعيد الإعلان', style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.md),
            ListTile(
              key: PromotionsScreen.startFieldKey,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_arrow_outlined),
              title: const Text('يظهر'),
              subtitle: Text(_day(_start)),
              onTap: () => _pick(start: true),
            ),
            ListTile(
              key: PromotionsScreen.endFieldKey,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.stop_outlined),
              title: const Text('يختفي'),
              subtitle: Text(_day(_end)),
              onTap: () => _pick(start: false),
            ),
            const SizedBox(height: Space.md),
            FilledButton(
              key: PromotionsScreen.saveDatesKey,
              onPressed: () =>
                  Navigator.of(context).pop((start: _start, end: _end)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Sizes.minTarget),
              ),
              child: const Text('احفظ'),
            ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
  }
}

String _day(DateTime date) => '${date.day}/${date.month}';

/// Refusing costs a sentence.
///
/// Without one the merchant has nothing to fix and will ask again with the same thing,
/// which costs the admin the same minute twice.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('سبب الرفض'),
      content: TextField(
        key: PromotionsScreen.reasonKey,
        controller: _reason,
        maxLines: 2,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'الصورة مش واضحة، النص فيه مبالغة…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: PromotionsScreen.confirmRejectKey,
          onPressed: () {
            final text = _reason.text.trim();
            if (text.isEmpty) return;
            Navigator.of(context).pop(text);
          },
          child: const Text('ارفض'),
        ),
      ],
    );
  }
}

/// The admin putting up a placement of their own.
///
/// Deliberately shorter than the merchant's request form. The owner is not asking for
/// anything — they are the approval — so there is no price to quote and no case to make;
/// what is left is which shop it points at, which channel it runs in, and what it says.
///
/// Dates are not asked for. A banner made now runs from now for a week, which is what
/// "put this up" means, and the merchant's own request form takes the same shortcut for
/// the same reason: a date picker for the common case is a step that earns nothing.
class _CreateForm extends ConsumerStatefulWidget {
  const _CreateForm();

  @override
  ConsumerState<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends ConsumerState<_CreateForm> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();

  String? _merchantId;
  PromotionChannel _channel = PromotionChannel.homeBanner;

  /// The ground the words sit on. Null is the brand gradient.
  String? _backgroundColor;

  /// A boost lifts a shop in the ranking and shows no words at all, so asking for a
  /// headline it will never render would be asking for nothing.
  bool get _needsText => _channel != PromotionChannel.boost;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final merchantId = _merchantId;
    if (merchantId == null) return;

    final now = ref.read(clockProvider)();
    Navigator.of(context).pop(
      Promotion(
        id: '',
        cityId: ref.read(currentCityProvider),
        merchantId: merchantId,
        channel: _channel,
        // Text only. An admin putting up a quick announcement has no artwork to hand,
        // and `promotions_image_has_media` refuses a row whose mode promises a picture
        // it does not carry — so the mode follows what is actually here.
        renderMode: PromotionRender.text,
        backgroundColor: _needsText ? _backgroundColor : null,
        title: _title.text.trim(),
        body: _body.text.trim(),
        startAt: now,
        endAt: now.add(const Duration(days: 7)),
        requestedBy: ref.read(currentIdentityProvider).value?.uid ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final merchants = ref.watch(allMerchantsProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'إعلان جديد',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: Space.lg),
                  switch (merchants) {
                    AsyncValue(hasError: true) => const InputDecorator(
                      decoration: InputDecoration(labelText: 'المطعم'),
                      child: Text('مقدرناش نجيب المطاعم. اقفل وافتح تاني.'),
                    ),
                    AsyncValue(hasValue: true, :final value?) =>
                      DropdownButtonFormField<String>(
                        key: PromotionsScreen.formMerchantKey,
                        initialValue: _merchantId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'المطعم'),
                        items: [
                          for (final merchant in value)
                            DropdownMenuItem(
                              value: merchant.id,
                              child: Text(
                                merchant.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (id) => setState(() => _merchantId = id),
                        validator: (v) =>
                            v != null && v.isNotEmpty ? null : 'اختار المطعم',
                      ),
                    _ => const InputDecorator(
                      decoration: InputDecoration(labelText: 'المطعم'),
                      child: Text('بنجيب المطاعم…'),
                    ),
                  },
                  const SizedBox(height: Space.md),
                  DropdownButtonFormField<PromotionChannel>(
                    key: PromotionsScreen.formChannelKey,
                    initialValue: _channel,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'المكان'),
                    items: [
                      for (final entry in PromotionsScreen.channelNames.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (c) => setState(() => _channel = c ?? _channel),
                  ),
                  if (_needsText) ...[
                    const SizedBox(height: Space.md),
                    TextFormField(
                      key: PromotionsScreen.formTitleKey,
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'العنوان'),
                      validator: (v) => v != null && v.trim().isNotEmpty
                          ? null
                          : 'اكتب العنوان',
                    ),
                    const SizedBox(height: Space.md),
                    TextFormField(
                      key: PromotionsScreen.formBodyKey,
                      controller: _body,
                      decoration: const InputDecoration(
                        labelText: 'التفاصيل (اختياري)',
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    Text(
                      'لون الخلفية',
                      style: LuqmaType.button.copyWith(
                        color: Theme.of(context).luqma.textSecondary,
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    BannerColorPicker(
                      selected: _backgroundColor,
                      onPicked: (hex) => setState(() => _backgroundColor = hex),
                    ),
                  ],
                  const SizedBox(height: Space.lg),
                  FilledButton(
                    key: PromotionsScreen.formSubmitKey,
                    onPressed: _submit,
                    child: const Text('حط الإعلان'),
                  ),
                  const SizedBox(height: Space.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
