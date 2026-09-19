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
  static const reopenKey = Key('issues.reopen');
  static const reopenReasonKey = Key('issues.reopenReason');
  static const confirmReopenKey = Key('issues.confirmReopen');

  @override
  ConsumerState<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends ConsumerState<IssuesScreen> {
  _IssueFilter _filter = _IssueFilter.all;
  String? _selectedIssueId;

  Future<void> _closeIssue(OrderIssue issue) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _CloseDialog(
        onConfirm: (note) async {
          final messenger = ScaffoldMessenger.of(context);
          final res = await ref
              .read(issueRepositoryProvider)
              .close(issue.id, adminNote: note);
          if (res.isOk && dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
            messenger.showSnackBar(
              const SnackBar(content: Text('تم إغلاق الشكوى بنجاح')),
            );
          }
          return res;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final issues = ref.watch(issuesQueueProvider);
    final layout = AdminLayout.of(context);
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    final selected = issues.value
        ?.where((i) => i.id == _selectedIssueId)
        .firstOrNull;

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
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) {
                        final issue = filtered[i];
                        return _IssueRow(
                          issue: issue,
                          isSelected: issue.id == _selectedIssueId,
                          onSelect: () =>
                              setState(() => _selectedIssueId = issue.id),
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

/// Formats issue time for Arabic display:
/// «النهارده 3:40م» / «امبارح 3:40م» / «12 سبتمبر 3:40م»
String formatIssueDateTime(DateTime when, {DateTime? now}) {
  final local = when.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final isToday =
      local.year == current.year &&
      local.month == current.month &&
      local.day == current.day;
  final yesterday = DateTime(current.year, current.month, current.day - 1);
  final isYesterday =
      local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day;

  var hour = local.hour % 12;
  if (hour == 0) hour = 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final marker = local.hour >= 12 ? 'م' : 'ص';
  final timeStr = '$hour:$minute$marker';

  if (isToday) {
    return 'النهارده $timeStr';
  } else if (isYesterday) {
    return 'امبارح $timeStr';
  } else {
    final monthName = luqmaMonthName(local.month);
    return '${local.day} $monthName $timeStr';
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
                                formatIssueDateTime(issue.createdAt!),
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

class _IssueDetail extends ConsumerWidget {
  const _IssueDetail({required this.issue, required this.onClose});

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReopenDialog(),
    );
    if (reason == null || reason.trim().isEmpty || !context.mounted) return;
    final result = await ref
        .read(issueRepositoryProvider)
        .reopen(issue.id, reason: reason);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result is Ok ? 'الشكوى اتفتحت تاني' : 'مقدرناش نفتحها. جرّب تاني.',
        ),
      ),
    );
  }

  final OrderIssue issue;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final createdAt = issue.createdAt;
    final dateStr = createdAt != null ? formatIssueDateTime(createdAt) : null;
    final orderAsync = ref.watch(orderProvider(issue.orderId));
    final order = orderAsync.value;

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
                    if (order != null) ...[
                      Text(
                        'طلب #${order.orderNumber}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'المحل: ${order.merchantName}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'العميل: ${order.customerName}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: Space.xs),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'الهاتف: ${order.customerPhone}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: Space.xs),
                          IconButton(
                            tooltip: 'اتصال بالعميل',
                            icon: Icon(
                              Icons.phone,
                              color: colors.brand,
                              size: 20,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: Sizes.minTarget,
                              minHeight: Sizes.minTarget,
                            ),
                            onPressed: () async {
                              await openExternalLink(
                                context,
                                ref,
                                Uri.parse('tel:${order.customerPhone}'),
                                whenUnavailable:
                                    'لا يمكن إجراء المكالمة على هذا الجهاز',
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'الإجمالي: ${strings.price(order.pricing.total)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.price,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else if (orderAsync.isLoading) ...[
                      const SizedBox(height: Space.xs),
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ] else ...[
                      Text(
                        'الطلب: #${issue.orderId}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    if (dateStr != null) ...[
                      const SizedBox(height: Space.xs),
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
                child: Text(issue.reason, style: theme.textTheme.bodyMedium),
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
                      const Spacer(),
                      // Closed by mistake, or the customer called back: a closed ticket
                      // was a dead end (QA review 2026-09-19).
                      OutlinedButton(
                        key: IssuesScreen.reopenKey,
                        onPressed: () => _reopen(context, ref),
                        child: const Text('إعادة فتح'),
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
  const _CloseDialog({required this.onConfirm});

  final Future<Result<void>> Function(String? note) onConfirm;

  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  final _note = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = LuqmaStrings.of(context);
    final colors = Theme.of(context).luqma;

    return AlertDialog(
      title: Text(strings.issuesCloseDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: TextStyle(color: colors.danger)),
            const SizedBox(height: Space.sm),
          ],
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: strings.issuesCloseDialogNoteLabel,
              hintText: strings.issuesCloseDialogNoteHint,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: IssuesScreen.cancelKey,
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(null),
          child: Text(strings.issuesCloseDialogCancel),
        ),
        FilledButton(
          key: IssuesScreen.confirmKey,
          onPressed: _isSubmitting
              ? null
              : () async {
                  setState(() {
                    _isSubmitting = true;
                    _errorMessage = null;
                  });
                  final noteText = _note.text.trim();
                  final res = await widget.onConfirm(
                    noteText.isEmpty ? null : noteText,
                  );
                  if (mounted && !res.isOk) {
                    setState(() {
                      _isSubmitting = false;
                      _errorMessage = 'فشل إغلاق الشكوى، حاول مرة أخرى';
                    });
                  }
                },
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(strings.issuesCloseDialogConfirm),
        ),
      ],
    );
  }
}

/// Why a closed ticket is being opened again — kept in its note, so the history reads.
class _ReopenDialog extends StatefulWidget {
  const _ReopenDialog();

  @override
  State<_ReopenDialog> createState() => _ReopenDialogState();
}

class _ReopenDialogState extends State<_ReopenDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إعادة فتح الشكوى'),
      content: TextField(
        key: IssuesScreen.reopenReasonKey,
        controller: _reason,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'ليه بتتفتح تاني؟',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('رجوع'),
        ),
        FilledButton(
          key: IssuesScreen.confirmReopenKey,
          onPressed: () {
            if (_reason.text.trim().isEmpty) {
              setState(() => _error = 'اكتب السبب');
              return;
            }
            Navigator.of(context).pop(_reason.text);
          },
          child: const Text('افتحها'),
        ),
      ],
    );
  }
}
