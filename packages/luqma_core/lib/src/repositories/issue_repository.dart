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

  /// Opens a closed ticket again — closed by mistake, or the customer called back. The
  /// reason is kept in the note, after whatever was written when it closed.
  Future<Result<void>> reopen(String id, {required String reason});
}

class SupabaseIssueRepository implements IssueRepository {
  SupabaseIssueRepository(this._db, {this.cap = 500});

  final SupabaseClient _db;

  /// How many tickets the queue shows at most, open ones first.
  ///
  /// It watched the whole table, unordered. PostgREST answers at most 1000 rows, and past
  /// that the page is arbitrary — typically the oldest — so a new open complaint could be
  /// missing from «الشكاوى» while the grid's count, computed server-side, said it was
  /// there (D7). Ordered open-first and newest-first, the cap only ever drops old closed
  /// tickets, and a queue with this many *open* ones has a bigger problem than a page.
  final int cap;

  @override
  Stream<List<OrderIssue>> watchIssues() {
    return watchRows(
      db: _db,
      table: 'order_issues',
      map: OrderIssue.fromRow,
      // 'open' sorts after 'closed', so descending puts the open ones first.
      orderBy: 'status',
      ascending: false,
      thenBy: 'created_at',
      thenAscending: false,
      limit: cap,
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

  @override
  Future<Result<void>> reopen(String id, {required String reason}) {
    return Result.guard(() async {
      final row = await _db
          .from('order_issues')
          .select('admin_note')
          .eq('id', id)
          .maybeSingle();
      if (row == null) throw const NotFoundFailure();
      final before = (row['admin_note'] as String?)?.trim();
      final note = [
        if (before != null && before.isNotEmpty) before,
        'اتفتحت تاني: ${reason.trim()}',
      ].join('\n');
      final changed = await _db
          .from('order_issues')
          .update({'status': 'open', 'admin_note': note})
          .eq('id', id)
          .select('id');
      if (changed.isEmpty) throw const NotFoundFailure();
    });
  }
}

/// In-memory issues, for tests and for building screens above it.
class FakeIssueRepository implements IssueRepository {
  FakeIssueRepository({List<OrderIssue> seed = const [], this.failure})
    : _issues = {for (final i in seed) i.id: i};

  final Map<String, OrderIssue> _issues;
  Failure? failure;

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

  @override
  Future<Result<void>> reopen(String id, {required String reason}) async {
    if (failure != null) return Result.err(failure!);
    final existing = _issues[id];
    if (existing == null) return const Result.err(NotFoundFailure());
    final before = existing.adminNote?.trim();
    _issues[id] = OrderIssue(
      id: existing.id,
      orderId: existing.orderId,
      customerUid: existing.customerUid,
      merchantId: existing.merchantId,
      reason: existing.reason,
      status: 'open',
      adminNote: [
        if (before != null && before.isNotEmpty) before,
        'اتفتحت تاني: ${reason.trim()}',
      ].join('\n'),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );
    return const Result.ok(null);
  }
}
