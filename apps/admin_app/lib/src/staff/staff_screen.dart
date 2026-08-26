import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'staff_controller.dart';

/// The platform's own accounts: admins, moderators, and the shops' owners and couriers.
///
/// Lists and deactivates. Creating an account stays in the server script until the
/// service-role path exists — the note says so rather than offering a button that
/// cannot do the one thing it promises.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  static const emptyKey = Key('staff.empty');
  static const toggleKey = Key('staff.toggle');

  static const _roles = {
    'admin': 'أدمن',
    'moderator': 'مشرف',
    'owner': 'صاحب مطعم',
    'courier': 'دليفري',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الفريق')),
      body: AdminContent(
        child: switch (staff) {
          AsyncValue(hasError: true, :final error?) => LuqmaErrorView(
              failure: error,
              onRetry: () => ref.invalidate(staffListProvider),
            ),
          AsyncValue(hasValue: true, :final value?) when value.isEmpty => Center(
              key: StaffScreen.emptyKey,
              child: Text(
                'مفيش حسابات لسه.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).luqma.textSecondary,
                    ),
              ),
            ),
          AsyncValue(hasValue: true, :final value?) => ListView.separated(
              padding: const EdgeInsets.all(Space.gutter),
              itemCount: value.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
              itemBuilder: (context, i) => _StaffRow(
                member: value[i],
                onToggle: () => _toggle(context, ref, value[i]),
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    StaffMember member,
  ) async {
    await ref
        .read(staffRepositoryProvider)
        .setActive(member.uid, active: !member.isActive);
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.member, required this.onToggle});

  final StaffMember member;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      constraints: const BoxConstraints(minHeight: Sizes.minTarget),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name?.isNotEmpty == true ? member.name! : 'حساب',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${StaffScreen._roles[member.role] ?? member.role} — '
                  '${member.scope == 'merchant' ? 'مطعم' : 'المنصة'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            key: StaffScreen.toggleKey,
            tooltip: member.isActive ? 'تعطيل' : 'تفعيل',
            icon: Icon(
              member.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
              color: member.isActive ? colors.danger : colors.brand,
            ),
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }
}
