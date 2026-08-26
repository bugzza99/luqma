import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/live_query.dart';
import '../models/admin.dart';
import '../result.dart';

/// The platform's own accounts: admins, moderators, and the shops' owners and couriers.
///
/// Creating an account is a server act — somebody must mint the Auth user — and it goes
/// through the `create-staff-account` Edge Function, which holds the service role and
/// checks that its caller is an active platform admin before spending it. This interface
/// is the app's half of that conversation; everything else here is ordinary reads.
abstract interface class StaffRepository {
  Stream<List<StaffMember>> watchStaff();

  /// Deactivating keeps the account and its history while shutting the door: the
  /// sign-in boundary refuses an inactive staff row's holder.
  Future<Result<void>> setActive(String uid, {required bool active});

  /// Mints a new account. [merchantId] is required for merchant-scope accounts and
  /// refused for platform ones — an owner without a shop would sign in to nothing.
  Future<Result<StaffMember>> createAccount({
    required String email,
    required String password,
    required String name,
    required String scope,
    required String role,
    String? merchantId,
  });
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

  @override
  Future<Result<StaffMember>> createAccount({
    required String email,
    required String password,
    required String name,
    required String scope,
    required String role,
    String? merchantId,
  }) {
    return Result.guard(() async {
      final response = await _db.functions.invoke(
        'create-staff-account',
        body: {
          'email': email,
          'password': password,
          'name': name,
          'scope': scope,
          'role': role,
          if (merchantId != null) 'merchantId': merchantId,
        },
      );

      // The function names its refusals so the screen can say which sentence to show.
      switch (response.status) {
        case >= 200 && < 300:
          break;
        case 409:
          throw const EmailTakenFailure();
        case 400:
          throw const ConflictFailure();
        case 401 || 403:
          throw const PermissionFailure();
        default:
          throw UnknownFailure('create-staff-account: HTTP ${response.status}');
      }

      final data = Map<String, Object?>.from(response.data as Map);
      return StaffMember(
        uid: data['uid'] as String,
        scope: scope,
        role: role,
        merchantId: merchantId,
        name: name.isEmpty ? null : name,
        isActive: true,
      );
    });
  }
}

/// In-memory staff, for tests and for building screens above it.
class FakeStaffRepository implements StaffRepository {
  FakeStaffRepository({List<StaffMember> seed = const [], this.failure})
    : _members = {for (final m in seed) m.uid: m};

  final Map<String, StaffMember> _members;
  final Failure? failure;

  /// Addresses this fake has handed out, so a duplicate create is refused the way
  /// production refuses it.
  final Set<String> _emails = {};

  /// Everything held right now, for assertions.
  List<StaffMember> get all => List.unmodifiable(_members.values);

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

  @override
  Future<Result<StaffMember>> createAccount({
    required String email,
    required String password,
    required String name,
    required String scope,
    required String role,
    String? merchantId,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (_emails.contains(email.trim().toLowerCase())) {
      return const Result.err(EmailTakenFailure());
    }
    _emails.add(email.trim().toLowerCase());
    final member = StaffMember(
      uid: 'fake-${_members.length + 1}',
      scope: scope,
      role: role,
      merchantId: merchantId,
      name: name.isEmpty ? null : name,
      isActive: true,
    );
    _members[member.uid] = member;
    return Result.ok(member);
  }
}
