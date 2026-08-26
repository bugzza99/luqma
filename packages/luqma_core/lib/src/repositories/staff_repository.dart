import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/live_query.dart';
import '../models/admin.dart';
import '../result.dart';

/// The platform's own accounts: admins, moderators, and the shops' owners and couriers.
///
/// Creating an account is a server act — somebody must mint the Auth user — so this
/// interface lists and deactivates only. Creation goes through the
/// `create-staff-account` Edge Function, which holds the service role and checks that
/// its caller is an admin before spending it.
abstract interface class StaffRepository {
  Stream<List<StaffMember>> watchStaff();

  /// Deactivating keeps the account and its history while shutting the door: the
  /// sign-in boundary refuses an inactive staff row's holder.
  Future<Result<void>> setActive(String uid, {required bool active});
}

class SupabaseStaffRepository implements StaffRepository {
  SupabaseStaffRepository(this._db);

  final SupabaseClient _db;

  @override
  Stream<List<StaffMember>> watchStaff() {
    return watchRows(
      db: _db,
      table: 'staff',
      map: StaffMember.fromRow,
    ).map((members) {
      final sorted = List.of(members)
        ..sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          return a.role.compareTo(b.role);
        });
      return sorted;
    });
  }

  @override
  Future<Result<void>> setActive(String uid, {required bool active}) {
    return Result.guard(() async {
      await _db
          .from('staff')
          .update({'is_active': active}).eq('uid', uid);
    });
  }
}

/// In-memory staff, for tests and for building screens above it.
class FakeStaffRepository implements StaffRepository {
  FakeStaffRepository({List<StaffMember> seed = const [], this.failure})
    : _members = {for (final m in seed) m.uid: m};

  final Map<String, StaffMember> _members;
  final Failure? failure;

  @override
  Stream<List<StaffMember>> watchStaff() {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(_members.values.toList());
  }

  @override
  Future<Result<void>> setActive(String uid, {required bool active}) async {
    if (failure != null) return Result.err(failure!);
    final existing = _members[uid];
    if (existing == null) return const Result.err(NotFoundFailure());
    _members[uid] = StaffMember(
      uid: existing.uid,
      scope: existing.scope,
      role: existing.role,
      merchantId: existing.merchantId,
      name: existing.name,
      phone: existing.phone,
      isActive: active,
    );
    return const Result.ok(null);
  }
}
