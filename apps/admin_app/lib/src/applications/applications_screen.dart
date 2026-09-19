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
                          setDialogState(() {
                            isSaving = false;
                            saveError = 'حصل خطأ في حفظ القرار — حاول تاني';
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
