import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'issues_controller.dart';

/// The ticket queue a customer raises into and nobody could read until now.
///
/// Open tickets first, closed ones still visible. Closing answers in one write, with an
/// optional note that is where "we phoned the merchant" lives.
class IssuesScreen extends ConsumerWidget {
  const IssuesScreen({super.key});

  static const emptyKey = Key('issues.empty');
  static const closeKey = Key('issues.close');
  static const cancelKey = Key('issues.cancel');
  static const confirmKey = Key('issues.confirm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(issuesQueueProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الشكاوى')),
      body: AdminContent(
        child: switch (issues) {
          AsyncValue(hasError: true, :final error?) => LuqmaErrorView(
              failure: error,
              onRetry: () => ref.invalidate(issuesQueueProvider),
            ),
          AsyncValue(hasValue: true, :final value?) when value.isEmpty => Center(
              key: IssuesScreen.emptyKey,
              child: Text(
                'مفيش شكاوى.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).luqma.textSecondary,
                    ),
              ),
            ),
          AsyncValue(hasValue: true, :final value?) => ListView.separated(
              padding: const EdgeInsets.all(Space.gutter),
              itemCount: value.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
              itemBuilder: (context, i) => _IssueRow(
                issue: value[i],
                onClose: () => _closeIssue(context, ref, value[i]),
              ),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Future<void> _closeIssue(
    BuildContext context,
    WidgetRef ref,
    OrderIssue issue,
  ) async {
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CloseDialog(),
    );
    // `||`, not `&&`. With `and` this only returned when the dialog was cancelled
    // *and* the screen had gone — so cancelling while still looking at it fell
    // through and closed the ticket anyway, which is the opposite of what the
    // person just asked for.
    if (note == null || !context.mounted) return;

    await ref.read(issueRepositoryProvider).close(issue.id, adminNote: note);
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.onClose});

  final OrderIssue issue;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(
          color: issue.isOpen ? colors.danger : colors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  issue.isOpen ? 'مفتوحة' : 'مقفولة',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: issue.isOpen ? colors.danger : colors.textSecondary,
                  ),
                ),
              ),
              if (issue.isOpen)
                TextButton(
                  key: IssuesScreen.closeKey,
                  onPressed: onClose,
                  child: const Text('اقفل'),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(issue.reason, style: theme.textTheme.bodyMedium),
          if (issue.adminNote != null && issue.adminNote!.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Text(
              issue.adminNote!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _CloseDialog extends StatefulWidget {
  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('قفل الشكوى'),
      content: TextField(
        controller: _note,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'ملاحظة (اختياري)',
          hintText: 'كلّمنا المطعم واتحلّت.',
        ),
      ),
      actions: [
        TextButton(
          key: IssuesScreen.cancelKey,
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: IssuesScreen.confirmKey,
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: const Text('اقفل الشكوى'),
        ),
      ],
    );
  }
}
