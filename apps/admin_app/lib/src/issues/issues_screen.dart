import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'issues_controller.dart';

/// Which issues to show in the queue.
enum _IssueFilter { all, open, closed }

/// The ticket queue a customer raises into and nobody could read until now.
///
/// Open tickets first, closed ones still visible. Closing answers in one write, with an
/// optional note that is where "we phoned the merchant" lives.
/// Restyled to A14_Issues queue and A15_IssueDetail detail view with responsive two-pane support.
class IssuesScreen extends ConsumerStatefulWidget {
  const IssuesScreen({super.key});

  static const emptyKey = Key('issues.empty');
  static const closeKey = Key('issues.close');
  static const cancelKey = Key('issues.cancel');
  static const confirmKey = Key('issues.confirm');

  @override
  ConsumerState<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends ConsumerState<IssuesScreen> {
  _IssueFilter _filter = _IssueFilter.all;
  String? _selectedIssueId;

  Future<void> _closeIssue(OrderIssue issue) async {
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

  @override
  Widget build(BuildContext context) {
    final issues = ref.watch(issuesQueueProvider);
    final layout = AdminLayout.of(context);
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    final selected = issues.value?.where((i) => i.id == _selectedIssueId).firstOrNull;

    // On narrow screens (phone), the issue detail replaces the queue list
    // so controls have full touch targets.
    if (!layout.showsTwoPanes && selected != null) {
      return _IssueDetailScreen(
        issue: selected,
        onBack: () => setState(() => _selectedIssueId = null),
        onClose: () => _closeIssue(selected),
      );
    }

    final listPane = LuqmaAsyncView(
      value: issues,
      onRetry: () => ref.invalidate(issuesQueueProvider),
      empty: LuqmaEmptyView(
        key: IssuesScreen.emptyKey,
        icon: Icons.forum_outlined,
        message: strings.issuesEmpty,
      ),
      isEmpty: (value) => value.isEmpty,
      builder: (context, allIssues) {
        final openCount = allIssues.where((i) => i.isOpen).length;
        final closedCount = allIssues.length - openCount;

        final filtered = switch (_filter) {
          _IssueFilter.all => allIssues,
          _IssueFilter.open => allIssues.where((i) => i.isOpen).toList(),
          _IssueFilter.closed => allIssues.where((i) => !i.isOpen).toList(),
        };

        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.gutter,
                vertical: Space.sm,
              ),
              child: Row(
                children: [
                  LuqmaChip(
                    label: '${strings.issuesFilterAll} (${allIssues.length})',
                    selected: _filter == _IssueFilter.all,
                    onTap: () => setState(() => _filter = _IssueFilter.all),
                  ),
                  const SizedBox(width: Space.sm),
                  LuqmaChip(
                    label: '${strings.issuesFilterOpen} ($openCount)',
                    selected: _filter == _IssueFilter.open,
                    onTap: () => setState(() => _filter = _IssueFilter.open),
                  ),
                  const SizedBox(width: Space.sm),
                  LuqmaChip(
                    label: '${strings.issuesFilterClosed} ($closedCount)',
                    selected: _filter == _IssueFilter.closed,
                    onTap: () => setState(() => _filter = _IssueFilter.closed),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? LuqmaEmptyView(
                      key: IssuesScreen.emptyKey,
                      icon: Icons.filter_alt_outlined,
                      message: strings.issuesEmpty,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Space.gutter),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) {
                        final issue = filtered[i];
                        return _IssueRow(
                          issue: issue,
                          isSelected: issue.id == _selectedIssueId,
                          onSelect: () => setState(() => _selectedIssueId = issue.id),
                          onClose: () => _closeIssue(issue),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );

    if (layout.showsTwoPanes) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.issuesTitle)),
        body: Row(
          children: [
            Expanded(flex: 2, child: listPane),
            VerticalDivider(width: 1, color: colors.hairline),
            Expanded(
              flex: 3,
              child: selected == null
                  ? _NothingSelected(strings: strings)
                  : _IssueDetail(
                      issue: selected,
                      onClose: () => _closeIssue(selected),
                    ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(strings.issuesTitle)),
      body: AdminContent(child: listPane),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected({required this.strings});

  final LuqmaStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LuqmaEmptyView(
        icon: Icons.forum_outlined,
        message: strings.issuesDetailNothingSelected,
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({
    required this.issue,
    required this.isSelected,
    required this.onSelect,
    required this.onClose,
  });

  final OrderIssue issue;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Material(
      color: colors.card,
      borderRadius: Radii.cardAll,
      elevation: 0,
      child: InkWell(
        onTap: onSelect,
        borderRadius: Radii.cardAll,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: Radii.cardAll,
            border: Border.all(
              color: isSelected ? colors.border : colors.hairline,
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: Elevations.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  color: issue.isOpen ? colors.danger : colors.hairline,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: issue.isOpen
                                    ? colors.danger.withValues(alpha: 0.1)
                                    : colors.surface,
                                borderRadius: Radii.pillAll,
                              ),
                              child: Text(
                                issue.isOpen
                                    ? strings.issuesStatusOpen
                                    : strings.issuesStatusClosed,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: issue.isOpen
                                      ? colors.danger
                                      : colors.textSecondary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (issue.createdAt != null)
                              Text(
                                '${issue.createdAt!.hour.toString().padLeft(2, '0')}:${issue.createdAt!.minute.toString().padLeft(2, '0')}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.sm),
                        Text(issue.reason, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          'طلب #${issue.orderId}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (issue.adminNote != null &&
                            issue.adminNote!.isNotEmpty) ...[
                          const SizedBox(height: Space.sm),
                          Text(
                            issue.adminNote!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: Space.sm),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: onSelect,
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Space.md,
                                  vertical: Space.xs,
                                ),
                              ),
                              child: Text(strings.issuesOpenAction),
                            ),
                            if (issue.isOpen) ...[
                              const SizedBox(width: Space.sm),
                              TextButton(
                                key: IssuesScreen.closeKey,
                                onPressed: onClose,
                                child: Text(strings.issuesCloseAction),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IssueDetailScreen extends StatelessWidget {
  const _IssueDetailScreen({
    required this.issue,
    required this.onBack,
    required this.onClose,
  });

  final OrderIssue issue;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = LuqmaStrings.of(context);
    final shortId = issue.id.length > 8 ? issue.id.substring(0, 8) : issue.id;

    return Scaffold(
      appBar: AppBar(
        title: Text('مشكلة #$shortId'),
        leading: IconButton(
          tooltip: strings.issuesBackTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: AdminContent(
        child: _IssueDetail(issue: issue, onClose: onClose),
      ),
    );
  }
}

class _IssueDetail extends StatelessWidget {
  const _IssueDetail({required this.issue, required this.onClose});

  final OrderIssue issue;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final createdAt = issue.createdAt;
    final dateStr = createdAt != null
        ? '${createdAt.year}/${createdAt.month}/${createdAt.day} · ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
        : null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.gutter),
            children: [
              Container(
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: Radii.cardAll,
                  border: Border.all(color: colors.hairline),
                  boxShadow: Elevations.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(issue.reason, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: Space.sm),
                    Text(
                      'الطلب: #${issue.orderId}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (dateStr != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'التاريخ: $dateStr',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.md),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.md,
                        vertical: Space.xs,
                      ),
                      decoration: BoxDecoration(
                        color: issue.isOpen
                            ? colors.danger.withValues(alpha: 0.1)
                            : colors.success.withValues(alpha: 0.1),
                        borderRadius: Radii.pillAll,
                      ),
                      child: Text(
                        issue.isOpen
                            ? strings.issuesStatusOpen
                            : strings.issuesStatusClosed,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: issue.isOpen ? colors.danger : colors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(
                strings.issuesDetailCustomerSaid,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Space.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: Radii.cardAll,
                  border: Border.all(color: colors.hairline),
                  boxShadow: Elevations.card,
                ),
                child: Text(
                  issue.reason,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (issue.adminNote != null && issue.adminNote!.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                Text(
                  strings.issuesDetailAdminNote,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Space.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: Radii.cardAll,
                    border: Border.all(color: colors.hairline),
                    boxShadow: Elevations.card,
                  ),
                  child: Text(
                    issue.adminNote!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: colors.card,
            border: Border(top: BorderSide(color: colors.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: issue.isOpen
                ? FilledButton(
                    key: const Key('issueDetail.close'),
                    onPressed: onClose,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.success,
                      minimumSize: const Size.fromHeight(Sizes.minTarget),
                    ),
                    child: Text(strings.issuesDetailResolveAction),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: colors.success,
                        size: Sizes.iconSm,
                      ),
                      const SizedBox(width: Space.sm),
                      Text(
                        strings.issuesDetailResolved,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
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
    final strings = LuqmaStrings.of(context);

    return AlertDialog(
      title: Text(strings.issuesCloseDialogTitle),
      content: TextField(
        controller: _note,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: strings.issuesCloseDialogNoteLabel,
          hintText: strings.issuesCloseDialogNoteHint,
        ),
      ),
      actions: [
        TextButton(
          key: IssuesScreen.cancelKey,
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(strings.issuesCloseDialogCancel),
        ),
        FilledButton(
          key: IssuesScreen.confirmKey,
          onPressed: () => Navigator.of(context).pop(_note.text.trim()),
          child: Text(strings.issuesCloseDialogConfirm),
        ),
      ],
    );
  }
}
