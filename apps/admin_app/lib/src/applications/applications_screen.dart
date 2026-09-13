import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';

/// Reviewing prospective couriers, restaurants and home kitchens.
///
/// An applicant leaves a name and a phone number through the way-in screen in MerchantApp.
/// The owner reviews each request here, telephones the applicant, and records a decision.
///
/// **Approving does NOT create an account here.** It marks the application decided. The
/// actual staff account is created separately by the owner through the staff screen,
/// which remains the only privilege path.
class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});

  static Key approveKey(String id) => Key('application.approve.$id');
  static Key rejectKey(String id) => Key('application.reject.$id');
  static const reviewNoteKey = Key('application.reviewNote');
  static const confirmKey = Key('application.confirm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(pendingStaffApplicationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات الانضمام'),
      ),
      body: AdminContent(
        child: LuqmaAsyncView<List<StaffApplication>>(
          value: stream,
          onRetry: () => ref.invalidate(pendingStaffApplicationsProvider),
          builder: (context, applications) =>
              _QueueList(applications: applications),
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
                  'قبول الطلب هنا يسجل قرار المراجعة فقط. إنشاء حساب المستخدم الفعلي وصلاحياته يتم من شاشة الفريق.',
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.luqma;

        return AlertDialog(
          title: Text(isApproval ? 'قبول طلب الانضمام' : 'رفض طلب الانضمام'),
          content: Column(
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
                    'القبول هنا يسجل قرار المراجعة فقط. لإنشاء الحساب الفعلي، استخدم شاشة الفريق.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ),
              TextField(
                key: ApplicationsScreen.reviewNoteKey,
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: isApproval ? 'ملاحظات المكالمة' : 'سبب الرفض وملاحظات المكالمة',
                  hintText: 'اكتب ما تم الاتفاق عليه خلال المكالمة تليفونياً',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: ApplicationsScreen.confirmKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: isApproval
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: colors.danger,
                      foregroundColor: colors.card,
                    ),
              child: Text(isApproval ? 'تأكيد القبول' : 'تأكيد الرفض'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final repo = ref.read(staffApplicationRepositoryProvider);
    final result = await repo.review(
      application.id,
      status: status,
      note: noteController.text,
    );

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isOk
              ? (isApproval ? 'تم قبول الطلب' : 'تم رفض الطلب')
              : 'حصل خطأ في حفظ القرار — حاول تاني',
        ),
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
    final initialLetter =
        application.name.trim().isNotEmpty ? application.name.trim()[0] : 'ع';

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
                      Text(
                        application.phone,
                        textDirection: TextDirection.ltr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
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
                    border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
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
