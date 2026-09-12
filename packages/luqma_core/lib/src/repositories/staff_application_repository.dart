import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/live_query.dart';
import '../models/staff_application.dart';
import '../result.dart';
import '../util/phone.dart';

/// Joining the platform: couriers, restaurants and home kitchens apply here.
///
/// An applicant is not signed in — they have no account, that is the point — so `anon`
/// may insert and do nothing else. The repository ensures the insert never asks for the
/// row back, because PostgREST's default `.select()` would fail on an RLS boundary that
/// grants insert alone.
///
/// The queue is readable and reviewable by an admin only.
abstract interface class StaffApplicationRepository {
  /// Leaves a name and number for the owner to review.
  ///
  /// Fails with [AlreadyAppliedFailure] if there is an existing pending application with
  /// this phone number, and [OfflineFailure] when the connection is down.
  Future<Result<void>> apply({
    required StaffApplicationKind kind,
    required String name,
    required String phone,
    String? note,
  });

  /// The open applications waiting for a phone call, newest first.
  Stream<List<StaffApplication>> watchPending();

  /// Records the owner's decision after speaking to the applicant.
  Future<Result<void>> review(
    String id, {
    required StaffApplicationStatus status,
    String? note,
    String? staffUid,
  });
}

class SupabaseStaffApplicationRepository implements StaffApplicationRepository {
  SupabaseStaffApplicationRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<void>> apply({
    required StaffApplicationKind kind,
    required String name,
    required String phone,
    String? note,
  }) async {
    return Result.guard(() async {
      try {
        // Plain insert with no .select(): `anon` has no select policy and asking for
        // the row back fails on 42501 permission-denied.
        await _db.from('staff_applications').insert({
          'kind': kind.name,
          'name': name.trim(),
          'phone': Phone.normalize(phone),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        });
      } on PostgrestException catch (e, st) {
        if (e.code == '23505' || e.message.contains('staff_applications_one_open')) {
          throw const AlreadyAppliedFailure();
        }
        Error.throwWithStackTrace(e, st);
      }
    });
  }

  @override
  Stream<List<StaffApplication>> watchPending() {
    return watchRows(
      db: _db,
      table: 'staff_applications',
      map: StaffApplication.fromRow,
      filters: const [RowFilter('status', 'pending')],
    ).map((applications) {
      final sorted = List.of(applications);
      sorted.sort((a, b) {
        final at = a.createdAt ?? DateTime(0);
        final bt = b.createdAt ?? DateTime(0);
        return bt.compareTo(at);
      });
      return sorted;
    });
  }

  @override
  Future<Result<void>> review(
    String id, {
    required StaffApplicationStatus status,
    String? note,
    String? staffUid,
  }) {
    return Result.guard(() async {
      await _db.rpc('review_staff_application', params: {
        'p_id': id,
        'p_status': status.name,
        if (note != null && note.trim().isNotEmpty) 'p_note': note.trim(),
        if (staffUid != null && staffUid.isNotEmpty) 'p_staff_uid': staffUid,
      });
    });
  }
}

/// In-memory application queue, for tests and building screens above it.
class FakeStaffApplicationRepository implements StaffApplicationRepository {
  FakeStaffApplicationRepository({
    List<StaffApplication> seed = const [],
    this.failure,
  }) : _applications = {for (final a in seed) a.id: a};

  final Map<String, StaffApplication> _applications;
  final Failure? failure;

  /// Everything held right now, for assertions.
  List<StaffApplication> get all => List.unmodifiable(_applications.values);

  final _changed = StreamController<void>.broadcast();

  Stream<T> _live<T>(T Function() read) => Stream.multi((listener) {
        listener.add(read());
        final sub = _changed.stream.listen((_) => listener.add(read()));
        listener.onCancel = sub.cancel;
      });

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() => _changed.close();

  @override
  Future<Result<void>> apply({
    required StaffApplicationKind kind,
    required String name,
    required String phone,
    String? note,
  }) async {
    if (failure != null) return Result.err(failure!);

    final normalized = Phone.normalize(phone);
    if (name.trim().runes.length < 2 || name.trim().runes.length > 80 ||
        normalized.runes.length < 6 || normalized.runes.length > 20 ||
        (note?.trim().runes.length ?? 0) > 500) {
      return const Result.err(ConflictFailure());
    }
    final hasOpen = _applications.values.any(
      (a) => a.isPending && Phone.normalize(a.phone) == normalized,
    );
    if (hasOpen) {
      return const Result.err(AlreadyAppliedFailure());
    }

    final id = 'fake-app-${_applications.length + 1}';
    _applications[id] = StaffApplication(
      id: id,
      kind: kind,
      name: name.trim(),
      phone: normalized,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      status: StaffApplicationStatus.pending,
      createdAt: DateTime.now(),
    );
    _notify();
    return const Result.ok(null);
  }

  @override
  Stream<List<StaffApplication>> watchPending() {
    if (failure != null) return Stream.error(failure!);
    return _live(() {
      final pending = _applications.values.where((a) => a.isPending).toList();
      pending.sort((a, b) {
        final at = a.createdAt ?? DateTime(0);
        final bt = b.createdAt ?? DateTime(0);
        return bt.compareTo(at);
      });
      return pending;
    });
  }

  @override
  Future<Result<void>> review(
    String id, {
    required StaffApplicationStatus status,
    String? note,
    String? staffUid,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (status == StaffApplicationStatus.pending) {
      return const Result.err(ConflictFailure());
    }
    final existing = _applications[id];
    if (existing == null || !existing.isPending) {
      return const Result.err(NotFoundFailure());
    }
    // The RPC trims the note before Postgres checks char_length (code points).
    // Reject before replacing the pending row, just as a failed UPDATE rolls back.
    if ((note?.trim().runes.length ?? 0) > 500) {
      return const Result.err(ConflictFailure());
    }
    _applications[id] = StaffApplication(
      id: existing.id,
      kind: existing.kind,
      name: existing.name,
      phone: existing.phone,
      note: existing.note,
      status: status,
      createdAt: existing.createdAt,
      reviewedAt: DateTime.now(),
      reviewedBy: 'fake-admin',
      reviewNote: note?.trim().isEmpty == true ? null : note?.trim(),
      staffUid: status == StaffApplicationStatus.approved ? staffUid : null,
    );
    _notify();
    return const Result.ok(null);
  }
}
