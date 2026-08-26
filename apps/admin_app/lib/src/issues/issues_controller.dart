import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'issues_controller.g.dart';

/// Every ticket, open first then newest. Closed ones stay visible — how last month's
/// complaints were answered is part of answering this month's.
@riverpod
Stream<List<OrderIssue>> issuesQueue(Ref ref) =>
    ref.watch(issueRepositoryProvider).watchIssues();
