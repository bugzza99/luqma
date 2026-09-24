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
  static Key editKey(String id) => Key('promotions.edit.$id');
  static const editTitleKey = Key('promotions.editTitle');
  static const editSaveKey = Key('promotions.editSave');

  static const createKey = Key('promotions.create');
  static const formMerchantKey = Key('promotions.form.merchant');

  /// How the platform's own announcement is named, in the picker and on its card.
  static const platformName = 'لقمة (المنصة)';
  static const formChannelKey = Key('promotions.form.channel');
  static const formTitleKey = Key('promotions.form.title');
  static const formBodyKey = Key('promotions.form.body');
  static const formSubmitKey = Key('promotions.form.submit');

  static Key cardKey(String id) => Key('promotions.card.$id');
  static Key approveKey(String id) => Key('promotions.approve.$id');
  static Key rejectKey(String id) => Key('promotions.reject.$id');
  static Key stopKey(String id) => Key('promotions.stop.$id');
  static const stopConfirmKey = Key('promotions.stop.confirm');
  static const stopCancelKey = Key('promotions.stop.cancel');
  static const pushConfirmKey = Key('promotions.push.confirm');
  static const pushCancelKey = Key('promotions.push.cancel');
  static const formStartDateKey = Key('promotions.form.startDate');
  static const formEndDateKey = Key('promotions.form.endDate');
  static Key pushWarningKey(String id) => Key('promotions.push.$id');
  static Key pushNotSentKey(String id) => Key('promotions.push.notSent.$id');
  static Key pushEmptyKey(String id) => Key('promotions.push.empty.$id');
  static Key pushReportKey(String id) => Key('promotions.push.report.$id');

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
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateForm(),
    );
  }
}

class _Request extends ConsumerStatefulWidget {
  const _Request({required this.promotion});

  final Promotion promotion;

  @override
  ConsumerState<_Request> createState() => _RequestState();
}

class _RequestState extends ConsumerState<_Request> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final merchantId = widget.promotion.merchantId;
    // Null for the platform's own push, which names no shop.
    final merchant =
        merchantId == null ? null : ref.watch(merchantProvider(merchantId)).value;

    return Container(
      key: PromotionsScreen.cardKey(widget.promotion.id),
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
                  merchant?.name ?? merchantId ?? PromotionsScreen.platformName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: Radii.pillAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Text(
                      'قيد المراجعة',
                      style: LuqmaType.caption.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            PromotionsScreen.channelNames[widget.promotion.channel]!,
            style: LuqmaType.caption.copyWith(color: colors.textSecondary),
          ),
          if (widget.promotion.channel == PromotionChannel.push) ...[
            const SizedBox(height: Space.sm),
            Container(
              key: PromotionsScreen.pushWarningKey(widget.promotion.id),
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
                      // Still marked apart from a banner, and now for what it does
                      // rather than for what it cannot do. The block was here because
                      // nothing sent these at all; `send_promotion_push` does, so the
                      // warning is the real one — this reaches phones, once, and the
                      // city gets only a few a week.
                      'ده بيوصل إشعار لكل العملاء في المدينة، مرة واحدة، أول ما يبدأ. '
                      'المدينة ليها عدد محدود في الأسبوع.',
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
          Text(
            widget.promotion.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (widget.promotion.body.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              widget.promotion.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: Sizes.iconSm,
                color: colors.price,
              ),
              const SizedBox(width: Space.xs),
              Flexible(
                child: Text(
                  'من ${_day(widget.promotion.startAt)} لـ ${_day(widget.promotion.endAt)}'
                  // Whether there is a price to agree at all: a placement inside the shop's
                  // plan is already paid for by the subscription (2026-09-17).
                  // «مفيش سعر مسجّل» rather than "agree a price": a placement the admin put
                  // up themselves also carries zero, and calling that one unpaid would be
                  // wrong (found in review).
                  '${widget.promotion.includedInPlan
                      ? ' · ضمن الباقة'
                      : widget.promotion.price > 0
                      ? ' · ${strings.price(widget.promotion.price)}'
                      : ' · مفيش سعر مسجّل'}',
                  style: LuqmaType.bodySmall.copyWith(
                    color: colors.price,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: PromotionsScreen.rejectKey(widget.promotion.id),
                  onPressed: _busy ? null : () => _reject(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.danger,
                    side: BorderSide(color: colors.danger),
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: const Text('رفض'),
                ),
              ),
              const SizedBox(width: Sizes.targetGap),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: PromotionsScreen.approveKey(widget.promotion.id),
                  onPressed: _busy ? null : () => _approve(context, ref),
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

    DateTime? startAt;
    DateTime? endAt;
    if (widget.promotion.startAt.isAfter(now)) {
      final startNow = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('يبدأ إمتى؟'),
          content: Text(
            'الطلب ده مكتوب إنه يبدأ ${_day(widget.promotion.startAt)}. '
            'تحب يشتغل من دلوقتي؟',
          ),
          actions: [
            TextButton(
              key: PromotionsScreen.keepDateKey,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('سيبه ${_day(widget.promotion.startAt)}'),
            ),
            FilledButton(
              key: PromotionsScreen.startNowKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('من دلوقتي'),
            ),
          ],
        ),
      );
      if (startNow == null || !mounted) return;
      if (startNow) {
        startAt = now;
        endAt = now.add(
          widget.promotion.endAt.difference(widget.promotion.startAt),
        );
      }
    }

    setState(() => _busy = true);
    final result = await ref
        .read(promotionRepositoryProvider)
        .approve(
          widget.promotion.id,
          approvedBy: by,
          startAt: startAt,
          endAt: endAt,
        );

    if (!mounted) return;
    setState(() => _busy = false);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Ok() => 'تمت الموافقة على الإعلان.',
          Err(:final failure) => switch (failure) {
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            PermissionFailure() => 'مش مسموحلك توافق على الإعلانات.',
            _ => 'معرفناش نوافق على الإعلان. جرّب تاني.',
          },
        }),
      ),
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );

    if (reason == null || !context.mounted) return;

    final by = ref.read(currentIdentityProvider).value?.uid;
    if (by == null) return;

    setState(() => _busy = true);
    final result = await ref
        .read(promotionRepositoryProvider)
        .reject(widget.promotion.id, reason: reason, by: by);

    if (!mounted) return;
    setState(() => _busy = false);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Ok() => 'تم رفض الإعلان.',
          Err(:final failure) => switch (failure) {
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            PermissionFailure() => 'مش مسموحلك ترفض الإعلانات.',
            _ => 'معرفناش نرفض الإعلان. جرّب تاني.',
          },
        }),
      ),
    );
  }
}

/// One placement on the board, with the control the admin was missing.
///
/// Deliberately not the queue card: there is nothing to approve or reject here — those
/// decisions are already taken — and repeating them would give an admin two places to
/// make the same call and two answers when they disagree. What is here is the one thing
/// only they can do: decide when it appears and when it goes away.
class _Placement extends ConsumerStatefulWidget {
  const _Placement({required this.promotion});

  final Promotion promotion;

  @override
  ConsumerState<_Placement> createState() => _PlacementState();
}

class _PlacementState extends ConsumerState<_Placement> {
  bool _stopping = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final now = ref.watch(clockProvider)();
    final merchantId = widget.promotion.merchantId;
    // Null for the platform's own push, which names no shop.
    final merchant =
        merchantId == null ? null : ref.watch(merchantProvider(merchantId)).value;

    // Approved is not live, and the board is the one screen where that distinction has
    // to be legible at a glance — it is the whole reason a scheduled banner looked to
    // the owner like a broken one.
    final (tone, label) = switch (widget.promotion.status) {
      PromotionStatus.requested => (colors.textSecondary, 'مستني مراجعة'),
      PromotionStatus.approved || PromotionStatus.active =>
        widget.promotion.isLiveAt(now)
            ? (colors.success, 'شغال دلوقتي')
            : (colors.textSecondary, 'هيبدأ ${_day(widget.promotion.startAt)}'),
      PromotionStatus.rejected => (colors.danger, 'مرفوض'),
      PromotionStatus.ended => (colors.textSecondary, 'خلص'),
    };

    return Container(
      key: PromotionsScreen.cardKey(widget.promotion.id),
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
                  merchant?.name ?? merchantId ?? PromotionsScreen.platformName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: Radii.pillAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: tone,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Text(
                      label,
                      style: LuqmaType.caption.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            PromotionsScreen.channelNames[widget.promotion.channel]!,
            style: LuqmaType.caption.copyWith(color: colors.textSecondary),
          ),
          if (widget.promotion.title.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              widget.promotion.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (widget.promotion.channel == PromotionChannel.push) ...[
            const SizedBox(height: Space.sm),
            if (widget.promotion.pushedAt == null)
              _PushNotSent(promotionId: widget.promotion.id)
            else
              _PushReport(promotionId: widget.promotion.id),
          ],
          const SizedBox(height: Space.sm),
          // A Wrap: the dates and two buttons beside them did not fit a phone's width.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: Sizes.iconSm,
                color: colors.price,
              ),
              const SizedBox(width: Space.xs),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.sm),
                child: Text(
                  'من ${_day(widget.promotion.startAt)} لـ ${_day(widget.promotion.endAt)}',
                  style: LuqmaType.bodySmall.copyWith(
                    color: colors.price,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                key: PromotionsScreen.datesKey(widget.promotion.id),
                onPressed: () => _moveDates(context, ref),
                icon: const Icon(Icons.event_outlined, size: Sizes.iconSm),
                label: const Text('المواعيد'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
                ),
              ),
              // A boost carries no words to correct.
              if (widget.promotion.channel != PromotionChannel.boost)
                TextButton.icon(
                  key: PromotionsScreen.editKey(widget.promotion.id),
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.edit_outlined, size: Sizes.iconSm),
                  label: const Text('عدّل الكلام'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
                  ),
                ),
              if (widget.promotion.isLiveAt(now)) ...[
                const SizedBox(width: Space.xs),
                TextButton.icon(
                  key: PromotionsScreen.stopKey(widget.promotion.id),
                  onPressed: _stopping ? null : () => _stop(context, ref),
                  icon: Icon(
                    Icons.stop_circle_outlined,
                    size: Sizes.iconSm,
                    color: colors.danger,
                  ),
                  label: Text('إيقاف', style: TextStyle(color: colors.danger)),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.danger,
                    minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Corrects the words and the ground of an approved or running placement in place. A
  /// typo on a live banner used to have no way out but stopping it (QA review 2026-09-19).
  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditWordsDialog(promotion: widget.promotion),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اتعدّل الإعلان.')),
      );
    }
  }

  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    final title = widget.promotion.title.trim();
    final thingName = title.isNotEmpty ? '«$title»' : 'الإعلان';
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إيقاف $thingName'),
        content: const Text(
          'الإعلان هيختفي فوراً من التطبيق ومش هيظهر للعملاء تاني.',
        ),
        actions: [
          TextButton(
            key: PromotionsScreen.stopCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            key: PromotionsScreen.stopConfirmKey,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).luqma.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('إيقاف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _stopping = true);
    final now = ref.read(clockProvider)();
    final stopped = await ref
        .read(promotionRepositoryProvider)
        .reschedule(
          widget.promotion.id,
          startAt: widget.promotion.startAt,
          endAt: now,
        );

    if (!mounted) return;
    setState(() => _stopping = false);

    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (stopped) {
          Ok() => 'تم إيقاف الإعلان.',
          Err(:final failure) => switch (failure) {
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            PermissionFailure() => 'مش مسموحلك توقف الإعلانات.',
            _ => 'معرفناش نوقف الإعلان. جرّب تاني.',
          },
        }),
      ),
    );
  }

  Future<void> _moveDates(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final window = await showModalBottomSheet<({DateTime start, DateTime end})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DatesSheet(promotion: widget.promotion),
    );
    if (window == null) return;

    final moved = await ref
        .read(promotionRepositoryProvider)
        .reschedule(
          widget.promotion.id,
          startAt: window.start,
          endAt: window.end,
        );

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

/// Inline on the board rather than behind another tap: the board already answers what
/// became of every campaign, and delivery is part of that answer rather than a second
/// task. It also leaves the queue's pre-approval warning exactly where the decision is
/// made, so consequence before approval and outcome after it do not replace each other.
class _PushReport extends ConsumerWidget {
  const _PushReport({required this.promotionId});

  final String promotionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(promotionPushReportProvider(promotionId));

    if (value.hasError && !value.hasValue) {
      return LuqmaErrorView(
        failure: value.error,
        compact: true,
        onRetry: () => ref.invalidate(promotionPushReportProvider(promotionId)),
      );
    }

    if (!value.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(Space.sm),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final report = value.value!;
    final colors = Theme.of(context).luqma;
    return Container(
      key: report.queued == 0
          ? PromotionsScreen.pushEmptyKey(promotionId)
          : PromotionsScreen.pushReportKey(promotionId),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.cardAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('نتيجة الإرسال', style: LuqmaType.bodyStrong),
              ),
              IconButton(
                tooltip: 'حدّث نتيجة الإرسال',
                onPressed: () =>
                    ref.invalidate(promotionPushReportProvider(promotionId)),
                icon: const Icon(Icons.refresh, size: Sizes.iconSm),
              ),
            ],
          ),
          if (report.queued == 0)
            Text(
              'الإشعار اتبعت، بس مفيش عملاء كانوا مستهدفين.',
              style: LuqmaType.body.copyWith(color: colors.textSecondary),
            )
          else
            Wrap(
              spacing: Space.md,
              runSpacing: Space.xs,
              children: [
                Text('اتجهزت: ${report.queued}', style: LuqmaType.body),
                Text('اتبعت: ${report.sent}', style: LuqmaType.body),
                Text('مستنية: ${report.waiting}', style: LuqmaType.body),
                Text(
                  'وقفت بعد 5 محاولات: ${report.failed}',
                  style: LuqmaType.body.copyWith(
                    color: report.failed > 0
                        ? colors.danger
                        : colors.textSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PushNotSent extends StatelessWidget {
  const _PushNotSent({required this.promotionId});

  final String promotionId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return Container(
      key: PromotionsScreen.pushNotSentKey(promotionId),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.cardAll,
      ),
      child: Text(
        'لسه ما اتبعتش للعملاء.',
        style: LuqmaType.body.copyWith(color: colors.textSecondary),
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
  String? _backgroundColor;
  bool _saving = false;

  late DateTime _startAt;
  late DateTime _endAt;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    _startAt = now;
    _endAt = now.add(const Duration(days: 7));
  }

  /// A boost lifts a shop in the ranking and shows no words at all, so asking for a
  /// headline it will never render would be asking for nothing.
  bool get _needsText => _channel != PromotionChannel.boost;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _startAt : _endAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _startAt.hour,
          _startAt.minute,
        );
        if (!_endAt.isAfter(_startAt)) {
          _endAt = _startAt.add(const Duration(days: 7));
        }
      } else {
        _endAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final merchantId = _merchantId;
    if (merchantId == null) return;

    if (!_endAt.isAfter(_startAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تاريخ النهاية لازم يكون بعد تاريخ البداية.'),
        ),
      );
      return;
    }

    if (_channel == PromotionChannel.push) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_title.text.trim()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_body.text.trim().isNotEmpty) ...[
                Text(_body.text.trim()),
                const SizedBox(height: Space.md),
              ],
              const Text('هيوصل لكل عملاء المدينة اللي مفعّلين الإشعارات'),
            ],
          ),
          actions: [
            TextButton(
              key: PromotionsScreen.pushCancelKey,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              key: PromotionsScreen.pushConfirmKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ابعت'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final by = ref.read(currentIdentityProvider).value?.uid;
    if (by == null) return;

    setState(() => _saving = true);

    final draft = Promotion(
      id: '',
      cityId: ref.read(currentCityProvider),
      // Empty is the platform's own push, which names no shop.
      merchantId: merchantId.isEmpty ? null : merchantId,
      channel: _channel,
      // Text only. An admin putting up a quick announcement has no artwork to hand,
      // and `promotions_image_has_media` refuses a row whose mode promises a picture
      // it does not carry — so the mode follows what is actually here.
      renderMode: PromotionRender.text,
      backgroundColor: _needsText ? _backgroundColor : null,
      title: _title.text.trim(),
      body: _body.text.trim(),
      startAt: _startAt,
      endAt: _endAt,
      requestedBy: by,
    );

    final result = await ref
        .read(promotionRepositoryProvider)
        .createApproved(draft, approvedBy: by);

    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case Ok():
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('الإعلان اتحط.')));
      case Err(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (failure) {
              PermissionFailure() => 'مش مسموحلك تحط إعلانات.',
              OfflineFailure() => 'مفيش نت — جرّب تاني.',
              _ => 'معرفناش نحط الإعلان. جرّب تاني.',
            }),
          ),
        );
    }
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
                          // Only a push may be the platform's own: a banner links to a
                          // shop and a boost ranks one. The empty value stands for none.
                          if (_channel == PromotionChannel.push)
                            const DropdownMenuItem(
                              value: '',
                              child: Text(PromotionsScreen.platformName),
                            ),
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
                        validator: (v) => v != null &&
                                (v.isNotEmpty || _channel == PromotionChannel.push)
                            ? null
                            : 'اختار المطعم',
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
                        if (entry.key != PromotionChannel.categoryBanner)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                    ],
                    onChanged: (c) => setState(() {
                      _channel = c ?? _channel;
                      // The platform is a choice for a push only; leaving push takes it
                      // away rather than keeping a selection the list no longer shows.
                      if (_channel != PromotionChannel.push && _merchantId == '') {
                        _merchantId = null;
                      }
                    }),
                  ),
                  const SizedBox(height: Space.md),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          key: PromotionsScreen.formStartDateKey,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.play_arrow_outlined),
                          title: const Text('من'),
                          subtitle: Text(_day(_startAt)),
                          onTap: () => _pickDate(start: true),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: ListTile(
                          key: PromotionsScreen.formEndDateKey,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.stop_outlined),
                          title: const Text('لحد'),
                          subtitle: Text(_day(_endAt)),
                          onTap: () => _pickDate(start: false),
                        ),
                      ),
                    ],
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
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving ? 'جاري الحفظ…' : 'حط الإعلان'),
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

class _EditWordsDialog extends ConsumerStatefulWidget {
  const _EditWordsDialog({required this.promotion});

  final Promotion promotion;

  @override
  ConsumerState<_EditWordsDialog> createState() => _EditWordsDialogState();
}

class _EditWordsDialogState extends ConsumerState<_EditWordsDialog> {
  late final _title = TextEditingController(text: widget.promotion.title);
  late final _body = TextEditingController(text: widget.promotion.body);
  late String? _color = widget.promotion.backgroundColor;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'اكتب العنوان');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref.read(promotionRepositoryProvider).adminEdit(
          widget.promotion.id,
          title: _title.text.trim(),
          body: _body.text.trim(),
          // A picture banner keeps no ground; only words sit on a colour.
          backgroundColor:
              widget.promotion.renderMode == PromotionRender.text ? _color : null,
        );
    if (!mounted) return;
    if (result.isOk) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = 'مقدرناش نحفظ التعديل — اللي كتبته لسه هنا. جرّب تاني.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('تعديل كلام الإعلان'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: PromotionsScreen.editTitleKey,
              controller: _title,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _body,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'التفاصيل'),
            ),
            if (widget.promotion.renderMode == PromotionRender.text) ...[
              const SizedBox(height: Space.md),
              BannerColorPicker(
                selected: _color,
                onPicked: (hex) => setState(() => _color = hex),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.luqma.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('رجوع'),
        ),
        FilledButton(
          key: PromotionsScreen.editSaveKey,
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'لحظة…' : 'احفظ'),
        ),
      ],
    );
  }
}
