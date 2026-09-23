import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import '../merchants/merchants_controller.dart';

/// Reviewing prospective couriers, restaurants and home kitchens.
///
/// An applicant leaves a name and a phone number through the way-in screen in MerchantApp.
/// The owner reviews each request here, telephones the applicant, and records a decision.
///
/// Approving builds the account in one transaction (`approve_staff_application`): the
/// staff row, and for a shop the merchant row too. Decided applications stay readable in
/// «اتقرر فيها», with the reason written at the time.
class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});

  static Key approveKey(String id) => Key('application.approve.$id');

  /// The way to look at a courier applicant's identity papers.
  static Key papersKey(String id) => Key('application.papers.$id');
  static const papersSheetKey = Key('application.papersSheet');
  static const papersEmptyKey = Key('application.papersEmpty');

  /// Removing a courier's papers: the control, the reason, and the confirmation.
  static const papersRemoveKey = Key('application.papersRemove');
  static const papersRemoveReasonKey = Key('application.papersRemoveReason');
  static const papersRemoveConfirmKey = Key('application.papersRemoveConfirm');
  static const zonePickerKey = Key('application.zone');
  static const shopPickerKey = Key('application.shop');
  static Key rejectKey(String id) => Key('application.reject.$id');
  static const reviewNoteKey = Key('application.reviewNote');
  static const confirmKey = Key('application.confirm');
  static const historyTabKey = Key('application.historyTab');
  static const historySearchKey = Key('application.historySearch');
  static Key decidedKey(String id) => Key('application.decided.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(pendingStaffApplicationsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('طلبات الانضمام'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'مستنية'),
              Tab(key: historyTabKey, text: 'اتقرر فيها'),
            ],
          ),
        ),
        body: AdminContent(
          child: TabBarView(
            children: [
              LuqmaAsyncView<List<StaffApplication>>(
                value: stream,
                onRetry: () => ref.invalidate(pendingStaffApplicationsProvider),
                builder: (context, applications) =>
                    _QueueList(applications: applications),
              ),
              const _History(),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({required this.applications});

  final List<StaffApplication> applications;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        // Plainly explain what approval does: it marks the application decided, and
        // does NOT create the account.
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: Sizes.iconSm, color: colors.brand),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'اتصل بالمتقدم الأول. القبول هيعمل الحساب وصلاحياته على طول — والرفض بيتسجل بسببه.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        if (applications.isEmpty)
          const LuqmaEmptyView(
            icon: Icons.inbox_outlined,
            message: 'مفيش طلبات في الانتظار',
          )
        else
          for (final app in applications) ...[
            _ApplicationCard(application: app),
            const SizedBox(height: Space.sm),
          ],
      ],
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.application});

  final StaffApplication application;

  /// The three photographs, full width, in a sheet the admin can scroll.
  ///
  /// A sheet rather than a row of thumbnails on the card: this is a national ID being
  /// checked against a name, and the whole point is to look at it properly. It is also
  /// why nothing here crops — `BoxFit.contain`, for the same reason the moderation queue
  /// stopped cropping: approving the middle of an image lets its edges through unseen.
  Future<void> _showPapers(BuildContext context, String applicantUid) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _PapersSheet(applicantUid: applicantUid),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref, {
    required StaffApplicationStatus status,
  }) async {
    final isApproval = status == StaffApplicationStatus.approved;
    final noteController = TextEditingController();
    final isCourier = application.kind == StaffApplicationKind.courier;
    String? zoneId;
    String? shopId;
    bool isSaving = false;
    String? saveError;

    // A courier is approved on their papers, and the database refuses one without them.
    // Asked before the dialog, from the repository rather than an auto-dispose provider
    // nobody is listening to, so the button can be off and say why instead of ending in
    // a refusal read as «حاول تاني» (D4). A read that fails decides nothing: the server
    // still has the last word, and its refusal is now said in words below.
    var noPapers = false;
    final applicantUid = application.applicantUid;
    if (isApproval && isCourier && applicantUid != null) {
      final papers =
          await ref.read(staffDocumentsRepositoryProvider).forPerson(applicantUid);
      noPapers = papers is Ok<StaffDocuments?> && papers.value == null;
      if (!context.mounted) return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          final colors = theme.luqma;

          return AlertDialog(
            title: Text(isApproval ? 'قبول طلب الانضمام' : 'رفض طلب الانضمام'),
            // Scrollable: the zone picker and the two explanations make this taller
            // than a phone dialog, and an overflow there hides the confirm button.
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isApproval)
                    Container(
                      padding: const EdgeInsets.all(Space.sm),
                      margin: const EdgeInsets.only(bottom: Space.md),
                      decoration: BoxDecoration(
                        color: colors.background,
                        borderRadius: Radii.cardAll,
                        border: Border.all(color: colors.hairline),
                      ),
                      child: Text(
                        isCourier
                            ? 'القبول هيعمل حساب المندوب ويربطه بالمحل اللي تختاره. تقدر تضيفله محلات تانية من «الفريق».'
                            : 'القبول هيعمل حساب صاحب المحل والمحل نفسه، وهيفضل «تحت المراجعة» لحد ما تكمّل بياناته.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  if (noPapers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: Text(
                        'المندوب لسه مارفعش صور البطاقة (الوش والضهر) والسيلفي، ومينفعش '
                        'يتقبل من غيرهم. كلّمه يرفعهم من تطبيق لقمة شريك وبعدين اقبله.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.danger,
                        ),
                      ),
                    ),
                  if (isApproval && application.applicantUid == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: Text(
                        'المتقدم ده طلب قبل ما التطبيق يطلب كلمة سر، فمعندوش حساب. ارفض الطلب ده '
                        'عشان الرقم يفضى، وقوله يقدّم تاني من النسخة الجديدة — أو اعملّه حساب من «الفريق».',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.danger,
                        ),
                      ),
                    ),
                  if (isApproval && application.applicantUid != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.md),
                      child: Consumer(
                        builder: (context, cRef, _) {
                          if (isCourier) {
                            final shopsAsync = cRef.watch(allMerchantsProvider);
                            return switch (shopsAsync) {
                              AsyncValue(hasError: true) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'فشل تحميل المحلات',
                                    style: TextStyle(color: colors.danger),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('إعادة المحاولة'),
                                    onPressed: () =>
                                        cRef.invalidate(allMerchantsProvider),
                                  ),
                                ],
                              ),
                              AsyncValue(isLoading: true) => const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: Space.sm,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: Space.sm),
                                    Text('جاري تحميل المحلات…'),
                                  ],
                                ),
                              ),
                              AsyncValue(hasValue: true, :final value?) =>
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  key: ApplicationsScreen.shopPickerKey,
                                  initialValue: shopId,
                                  decoration: const InputDecoration(
                                    labelText: 'يشتغل مع محل',
                                  ),
                                  items: [
                                    for (final shop in value)
                                      DropdownMenuItem(
                                        value: shop.id,
                                        child: Text(shop.name),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setDialogState(() => shopId = v),
                                ),
                              _ => const SizedBox.shrink(),
                            };
                          } else {
                            final zonesAsync = cRef.watch(zonesProvider);
                            return switch (zonesAsync) {
                              AsyncValue(hasError: true) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'فشل تحميل المناطق',
                                    style: TextStyle(color: colors.danger),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('إعادة المحاولة'),
                                    onPressed: () =>
                                        cRef.invalidate(zonesProvider),
                                  ),
                                ],
                              ),
                              AsyncValue(isLoading: true) => const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: Space.sm,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: Space.sm),
                                    Text('جاري تحميل المناطق…'),
                                  ],
                                ),
                              ),
                              AsyncValue(hasValue: true, :final value?) =>
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  key: ApplicationsScreen.zonePickerKey,
                                  initialValue: zoneId,
                                  decoration: const InputDecoration(
                                    labelText: 'المنطقة',
                                  ),
                                  items: [
                                    for (final zone in value)
                                      DropdownMenuItem(
                                        value: zone.id,
                                        child: Text(zone.name),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setDialogState(() => zoneId = v),
                                ),
                              _ => const SizedBox.shrink(),
                            };
                          }
                        },
                      ),
                    ),
                  TextField(
                    key: ApplicationsScreen.reviewNoteKey,
                    controller: noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: isApproval
                          ? 'ملاحظات المكالمة'
                          : 'سبب الرفض وملاحظات المكالمة',
                      hintText:
                          'اكتب ما تم الاتفاق عليه خلال المكالمة تليفونياً',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (saveError != null) ...[
                    const SizedBox(height: Space.sm),
                    Text(
                      saveError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                key: ApplicationsScreen.confirmKey,
                // Approval cannot proceed without what it needs to build: no account to
                // approve into, no zone for a shop, no shop for a courier.
                onPressed:
                    isSaving ||
                        (isApproval &&
                            (application.applicantUid == null ||
                                noPapers ||
                                (isCourier ? shopId == null : zoneId == null)))
                    ? null
                    : () async {
                        setDialogState(() {
                          isSaving = true;
                          saveError = null;
                        });

                        final repo = ref.read(
                          staffApplicationRepositoryProvider,
                        );
                        final result = isApproval
                            ? await repo.approve(
                                application.id,
                                zoneId: isCourier ? null : zoneId,
                                merchantId: isCourier ? shopId : null,
                                note: noteController.text,
                              )
                            : await repo.review(
                                application.id,
                                status: status,
                                note: noteController.text,
                              );

                        if (!dialogContext.mounted) return;

                        if (result.isOk) {
                          Navigator.of(dialogContext).pop();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isApproval
                                      ? (isCourier
                                            ? 'اتعمل حساب المندوب'
                                            : 'اتعمل الحساب والمحل')
                                      : 'تم رفض الطلب',
                                ),
                              ),
                            );
                          }
                        } else {
                          // Each refusal the server names, in words: «حاول تاني» is
                          // only true of a dropped line, and it was said for all of them
                          // — including an application another admin already decided,
                          // which no retry can ever change (D4).
                          setDialogState(() {
                            isSaving = false;
                            saveError = switch (result.failureOrNull) {
                              ValidationFailure() when isApproval && isCourier =>
                                'المندوب لسه مارفعش صور البطاقة والسيلفي، فمينفعش يتقبل.',
                              ValidationFailure() =>
                                'البيانات ناقصة — اتأكد من المنطقة أو المحل اللي اخترته.',
                              NotFoundFailure() => 'الطلب ده اتقرّر قبل كده.',
                              ConflictFailure() =>
                                'الشخص ده عنده حساب في الفريق بالفعل.',
                              PermissionFailure() => 'مش مسموح لك تاخد القرار ده.',
                              OfflineFailure() => 'مفيش نت — جرّب تاني.',
                              _ => 'حصل خطأ في حفظ القرار — حاول تاني',
                            };
                          });
                        }
                      },
                style: isApproval
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: colors.danger,
                        foregroundColor: colors.card,
                      ),
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isApproval ? 'تأكيد القبول' : 'تأكيد الرفض'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final (kindLabel, badgeColor, badgeBg) = switch (application.kind) {
      StaffApplicationKind.courier => (
        'مندوب توصيل',
        colors.brand,
        colors.brand.withValues(alpha: 0.12),
      ),
      StaffApplicationKind.restaurant => (
        'مطعم',
        colors.price,
        colors.accent.withValues(alpha: 0.18),
      ),
      StaffApplicationKind.homeKitchen => (
        'أكل بيتي',
        colors.success,
        colors.success.withValues(alpha: 0.14),
      ),
    };

    final note = application.note;
    final initialLetter = application.name.trim().isNotEmpty
        ? application.name.trim()[0]
        : 'ع';

    return Material(
      color: colors.card,
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: badgeColor,
                  child: Text(
                    initialLetter,
                    style: TextStyle(
                      color: colors.onBrand,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        application.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      // A Wrap: beside the avatar and the kind badge there is no room for the
                      // number and both buttons on one line of a phone.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            application.phone,
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: Space.xs),
                          IconButton(
                            icon: const Icon(
                              Icons.phone_outlined,
                              size: Sizes.iconSm,
                            ),
                            tooltip: 'اتصال',
                            onPressed: () => openExternalLink(
                              context,
                              ref,
                              Uri.parse('tel:${application.phone}'),
                              whenUnavailable: 'مفيش تطبيق اتصال متاح',
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.copy_outlined,
                              size: Sizes.iconSm,
                            ),
                            tooltip: 'نسخ الرقم',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: application.phone),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('اتنسخ الرقم')),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm,
                    vertical: Space.xs,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: Radii.pillAll,
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    kindLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.sm),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: Radii.cardAll,
                  border: Border.all(color: colors.hairline),
                ),
                child: Text(
                  note,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
            // A courier is approved on their papers, so the way to look at them sits with
            // the decision rather than behind it. Putting it inside the approve dialog
            // would mean the admin had already decided before they could see the ID.
            if (application.kind == StaffApplicationKind.courier &&
                application.applicantUid != null) ...[
              const SizedBox(height: Space.md),
              OutlinedButton.icon(
                key: ApplicationsScreen.papersKey(application.id),
                onPressed: () => _showPapers(context, application.applicantUid!),
                icon: const Icon(Icons.badge_outlined, size: Sizes.iconSm),
                label: const Text('شوف البطاقة'),
              ),
            ],
            const SizedBox(height: Space.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: ApplicationsScreen.rejectKey(application.id),
                  onPressed: () => _decide(
                    context,
                    ref,
                    status: StaffApplicationStatus.rejected,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.danger,
                    side: BorderSide(
                      color: colors.danger.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Text('رفض'),
                ),
                const SizedBox(width: Space.sm),
                // A moderator works this queue and cannot close it: approval mints the
                // `staff` row, which is the one permission that hands out every other
                // one, and the database refuses it
                // (`20261024010000_and_who_mints_an_account.sql`). Rejecting mints
                // nothing and stays theirs. Saying so here is the difference between a
                // divided job and a button that fails.
                if (ref.watch(staffIdentityProvider).isModerator)
                  Flexible(
                    child: Text(
                      'القبول بيعمل الحساب، وده للأدمن. ابعتله الطلب بعد المكالمة.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  )
                else
                  FilledButton(
                    key: ApplicationsScreen.approveKey(application.id),
                    onPressed: () => _decide(
                      context,
                      ref,
                      status: StaffApplicationStatus.approved,
                    ),
                    child: const Text('قبول'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Applications already decided — who called, what was agreed or why they were refused.
/// A call from last month used to have nowhere to be looked up (QA review 2026-09-19).
final decidedApplicationsProvider =
    FutureProvider.autoDispose<List<StaffApplication>>((ref) async {
  final result = await ref.read(staffApplicationRepositoryProvider).decided();
  return result.valueOrThrow;
});

class _History extends ConsumerStatefulWidget {
  const _History();

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final decided = ref.watch(decidedApplicationsProvider);

    return LuqmaAsyncView<List<StaffApplication>>(
      value: decided,
      onRetry: () => ref.invalidate(decidedApplicationsProvider),
      builder: (context, all) {
        final query = ArabicText.normalize(_query.trim());
        final digits = Phone.normalize(_query);
        final shown = [
          for (final a in all)
            if (query.isEmpty ||
                ArabicText.normalize(a.name).contains(query) ||
                (digits.isNotEmpty && a.phone.contains(digits)))
              a,
        ];
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(decidedApplicationsProvider);
            await ref
                .read(decidedApplicationsProvider.future)
                .then((_) {}, onError: (_) {});
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.gutter),
            children: [
              TextField(
                key: ApplicationsScreen.historySearchKey,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'دوّر بالاسم أو الرقم',
                ),
              ),
              const SizedBox(height: Space.md),
              if (shown.isEmpty)
                LuqmaEmptyView(
                  icon: Icons.history_rounded,
                  message: all.isEmpty
                      ? 'لسه متقررش في أي طلب'
                      : 'مفيش طلب بالاسم أو الرقم ده',
                )
              else
                for (final a in shown) ...[
                  Container(
                    key: ApplicationsScreen.decidedKey(a.id),
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
                              child: Text(a.name, style: theme.textTheme.titleMedium),
                            ),
                            Text(
                              a.status == StaffApplicationStatus.approved
                                  ? 'اتقبل'
                                  : 'اترفض',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: a.status == StaffApplicationStatus.approved
                                    ? colors.success
                                    : colors.danger,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          [
                            switch (a.kind) {
                              StaffApplicationKind.courier => 'مندوب توصيل',
                              StaffApplicationKind.restaurant => 'مطعم',
                              StaffApplicationKind.homeKitchen => 'أكل بيتي',
                            },
                            a.phone,
                            if (a.reviewedAt != null)
                              '${a.reviewedAt!.day}/${a.reviewedAt!.month}/${a.reviewedAt!.year}',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                        if ((a.reviewNote ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: Space.xs),
                          Text(a.reviewNote!.trim(), style: theme.textTheme.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                ],
            ],
          ),
        );
      },
    );
  }
}

/// A courier applicant's identity papers, fetched and signed for as long as it takes to
/// look at them.
///
/// Loading, error and empty are three different answers and this draws three different
/// things. "This applicant uploaded nothing" is a sentence the owner says on the
/// telephone; "the connection dropped" is not, and a screen that says the first when it
/// means the second sends somebody to ring a courier who did everything right.
class _PapersSheet extends ConsumerWidget {
  const _PapersSheet({required this.applicantUid});

  final String applicantUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final papers = ref.watch(staffDocumentsForProvider(applicantUid));

    return SafeArea(
      key: ApplicationsScreen.papersSheetKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: switch (papers) {
          // hasError first: a provider that fails before it has ever emitted stays
          // AsyncLoading with the error hanging off it, so the error arm never fires and
          // the sheet spins for ever.
          AsyncValue(hasError: true, :final error) => LuqmaErrorView(
              failure: error,
              onRetry: () => ref.invalidate(staffDocumentsForProvider(applicantUid)),
            ),
          AsyncValue(value: null, isLoading: true) => const Padding(
              padding: EdgeInsets.all(Space.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
          AsyncValue(value: null) => Padding(
              key: ApplicationsScreen.papersEmptyKey,
              padding: const EdgeInsets.all(Space.lg),
              child: Text(
                'المتقدم ده مرفعش صور البطاقة. مش هينفع تقبله من غيرها — كلّمه يقدّم تاني '
                'من النسخة الجديدة من التطبيق.',
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
          AsyncValue(value: final StaffDocuments found) => SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('صور البطاقة', style: theme.textTheme.titleMedium),
                  const SizedBox(height: Space.md),
                  for (final (label, path) in [
                    ('وش البطاقة', found.idFrontPath),
                    ('ضهر البطاقة', found.idBackPath),
                    ('سيلفي وهو ماسك البطاقة', found.selfiePath),
                  ]) ...[
                    Text(label, style: theme.textTheme.labelLarge),
                    const SizedBox(height: Space.xs),
                    _SignedImage(path: path),
                    const SizedBox(height: Space.md),
                  ],
                  // Removing papers is an admin's act and it is recorded with a reason
                  // (`admin_delete_staff_documents`). It lives here rather than on the
                  // card because it is a judgement about the photographs themselves:
                  // somebody uploaded the wrong thing, somebody else's card, or something
                  // that should not be stored at all.
                  if (ref.watch(staffIdentityProvider).isPlatformAdmin) ...[
                    const Divider(),
                    const SizedBox(height: Space.sm),
                    Text(
                      'لو الصور غلط أو مش بتاعته، شيلها وهو هيرفعها تاني. الثلاثة بيروحوا '
                      'مع بعض، لأن الطلب بيتقبل على الثلاثة.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: Space.sm),
                    OutlinedButton.icon(
                      key: ApplicationsScreen.papersRemoveKey,
                      onPressed: () async {
                        final removed = await showDialog<bool>(
                          context: context,
                          builder: (_) => _RemovePapersDialog(uid: applicantUid),
                        );
                        if (removed ?? false) {
                          ref.invalidate(staffDocumentsForProvider(applicantUid));
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.danger,
                        side: BorderSide(color: colors.danger.withValues(alpha: 0.5)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: Sizes.iconSm),
                      label: const Text('شيل الصور'),
                    ),
                  ],
                ],
              ),
            ),
        },
      ),
    );
  }
}

/// Removing somebody's papers, with the reason the server requires.
///
/// A widget rather than a `StatefulBuilder` over a controller made outside it: the
/// controller has to outlive the dialog's closing animation, and disposing it the moment
/// `showDialog` returns throws while the route is still painting itself out. A `State`
/// owns it and disposes it when the element really goes, which is the only place that
/// knows when that is.
///
/// The reason is not a formality and not this screen's idea. The function refuses a blank
/// one, because the audit row exists to answer «why are this courier's papers gone» and
/// one that may be empty does not answer it.
class _RemovePapersDialog extends ConsumerStatefulWidget {
  const _RemovePapersDialog({required this.uid});

  final String uid;

  @override
  ConsumerState<_RemovePapersDialog> createState() => _RemovePapersDialogState();
}

class _RemovePapersDialogState extends ConsumerState<_RemovePapersDialog> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final result = await ref
        .read(staffDocumentsRepositoryProvider)
        .removeFor(widget.uid, reason: _reason.text.trim());
    if (!mounted) return;
    switch (result) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final failure):
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(switch (failure) {
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            PermissionFailure() => 'مش من حقك تشيل الصور.',
            ValidationFailure() => 'اكتب السبب الأول.',
            // The papers are already gone: somebody else removed them, or the retention
            // sweep reached them. Saying «we failed» would be wrong — what was asked for
            // is true.
            NotFoundFailure() => 'الصور مش موجودة أصلاً.',
            _ => 'مقدرناش نشيل الصور. جرّب تاني.',
          })),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تشيل صور البطاقة؟'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'الصور هتتمسح خالص ومش هترجع، وهو هيحتاج يرفعها تاني قبل ما تقدر تقبله.',
          ),
          const SizedBox(height: Space.md),
          TextField(
            key: ApplicationsScreen.papersRemoveReasonKey,
            controller: _reason,
            enabled: !_busy,
            autofocus: true,
            // Without this nothing rebuilds as the reason is typed, so the confirm
            // button — disabled until there is one — stays dead while the admin looks at
            // the sentence they have just written.
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'السبب',
              hintText: 'صورة مش واضحة / البطاقة مش بتاعته',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('بلاش'),
        ),
        FilledButton(
          key: ApplicationsScreen.papersRemoveConfirmKey,
          // Single-flight: a second tap while the first is in flight sends a second
          // deletion for papers that are already gone, and the reply to that is «no papers
          // on file» — which reads as a failure for a request that worked.
          onPressed: _busy || _reason.text.trim().isEmpty ? null : _confirm,
          child: _busy
              ? const SizedBox(
                  width: Sizes.iconSm,
                  height: Sizes.iconSm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('شيلها'),
        ),
      ],
    );
  }
}

/// One photograph out of the private bucket.
///
/// The link is asked for here rather than alongside the row, so it is minted when
/// somebody actually looks and expires shortly after they stop. A signed link for a
/// national ID that lives as long as the screen does is a public URL with extra steps.
class _SignedImage extends ConsumerWidget {
  const _SignedImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;

    return FutureBuilder<Result<String>>(
      future: ref.read(staffDocumentsRepositoryProvider).signedUrl(path),
      builder: (context, snapshot) {
        final url = snapshot.data?.valueOrNull;
        if (url == null) {
          return Container(
            height: 180,
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: Radii.cardAll,
              border: Border.all(color: colors.hairline),
            ),
            child: Center(
              child: snapshot.connectionState == ConnectionState.done
                  ? Icon(Icons.broken_image_outlined, color: colors.textSecondary)
                  : const CircularProgressIndicator(),
            ),
          );
        }
        return ClipRRect(
          borderRadius: Radii.cardAll,
          child: Image.network(
            url,
            height: 260,
            // Never cropped: an admin approving the middle of an ID has not seen its
            // edges, and the edges are where a card says when it expires.
            fit: BoxFit.contain,
            errorBuilder: (context, _, _) => Container(
              height: 180,
              color: colors.background,
              child: Center(
                child: Icon(Icons.broken_image_outlined, color: colors.textSecondary),
              ),
            ),
          ),
        );
      },
    );
  }
}
