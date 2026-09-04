import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/live_query.dart';
import '../models/admin.dart';
import '../result.dart';

/// The ticket queue, as AdminApp works it.
///
/// A customer can raise a ticket; without this screen it is a complaint nobody can
/// read. The queue watches every ticket live — open ones first, but closed ones stay
/// visible, because how last month's complaints were answered is part of answering
/// this month's.
abstract interface class IssueRepository {
  /// Every ticket, open first then newest.
  Stream<List<OrderIssue>> watchIssues();

  /// Answers and closes in one write. Closing without a note is allowed — some
  /// tickets answer themselves — but the note is where "we phoned the merchant"
  /// lives, and that sentence is the point of the screen.
  Future<Result<void>> close(String id, {String? adminNote});
}

class SupabaseIssueRepository implements IssueRepository {
  SupabaseIssueRepository(this._db);

  final SupabaseClient _db;

  @override
  Stream<List<OrderIssue>> watchIssues() {
    return watchRows(
      db: _db,
      table: 'order_issues',
      map: OrderIssue.fromRow,
    ).map((issues) {
      final sorted = List.of(issues);
      sorted.sort((a, b) {
        // Open before closed; within each group, newest first.
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        final at = a.createdAt ?? DateTime(0);
        final bt = b.createdAt ?? DateTime(0);
        return bt.compareTo(at);
      });
      return sorted;
    });
  }

  @override
  Future<Result<void>> close(String id, {String? adminNote}) {
    return Result.guardWrite(
      () => _db.from('order_issues').update({
        'status': OrderIssue.closed,
        if (adminNote != null && adminNote.trim().isNotEmpty)
          'admin_note': adminNote.trim(),
      }).eq('id', id).select('id'),
      (_) {},
    );
  }
}

/// In-memory issues, for tests and for building screens above it.
class FakeIssueRepository implements IssueRepository {
  FakeIssueRepository({List<OrderIssue> seed = const [], this.failure})
    : _issues = {for (final i in seed) i.id: i};

  final Map<String, OrderIssue> _issues;
  final Failure? failure;

  @override
  Stream<List<OrderIssue>> watchIssues() {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(_sorted());
  }

  List<OrderIssue> _sorted() {
    final all = _issues.values.toList()
      ..sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        final at = a.createdAt ?? DateTime(0);
        final bt = b.createdAt ?? DateTime(0);
        return bt.compareTo(at);
      });
    return all;
  }

  @override
  Future<Result<void>> close(String id, {String? adminNote}) async {
    if (failure != null) return Result.err(failure!);
    final existing = _issues[id];
    if (existing == null) return const Result.err(NotFoundFailure());
    _issues[id] = OrderIssue(
      id: existing.id,
      orderId: existing.orderId,
      customerUid: existing.customerUid,
      merchantId: existing.merchantId,
      reason: existing.reason,
      status: OrderIssue.closed,
      adminNote: adminNote,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    return const Result.ok(null);
  }
}
