import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin.dart';
import '../result.dart';
import 'customer_repository.dart';
import 'staff_repository.dart';

/// The dashboard and statistics numbers, answered by the server.
///
/// Both are aggregates over whole tables — the one thing a client cannot be trusted to
/// ask itself. PostgREST has no GROUP BY, so they are SQL functions in
/// `20260824150000_admin_completion.sql`; this interface is the seam the screens speak
/// to, so a dashboard can be built and tested against a fake rather than a database.
abstract interface class AdminRepository {
  /// The four numbers the owner opens the app to see.
  Future<Result<AdminToday>> today();

  /// Who is on the platform and how it is moving.
  Future<Result<AdminStatistics>> statistics();

  /// What is waiting, by module — the numbers on the home grid's tiles.
  ///
  /// One call rather than one per tile: eleven round trips to draw one screen is eleven
  /// chances to be slow on a phone in a shop, and they would land at eleven different
  /// moments so the grid would fill in raggedly.
  Future<Result<AdminAttention>> attention();

  /// Deletes any customer, merchant owner, or courier account. Refuses platform staff.
  Future<Result<void>> deleteAccount(String uid);

  /// Reports active users today, past 7 days and past 30 days per app.
  Future<Result<ActiveUsers>> activeUsers();
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<AdminToday>> today() {
    return Result.guard(() async {
      final row = await _db.rpc('admin_today');
      return AdminToday.fromJson(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<Result<AdminStatistics>> statistics() {
    return Result.guard(() async {
      final row = await _db.rpc('admin_statistics');
      return AdminStatistics.fromJson(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<Result<AdminAttention>> attention() {
    return Result.guard(() async {
      final row = await _db.rpc('admin_attention');
      return AdminAttention.fromJson(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<Result<void>> deleteAccount(String uid) {
    return Result.guard(
      () => _db.rpc('admin_delete_account', params: {'p_uid': uid}),
    );
  }

  @override
  Future<Result<ActiveUsers>> activeUsers() {
    return Result.guard(() async {
      final rows = await _db.rpc('admin_active_users');
      return ActiveUsers.fromRows(rows as List? ?? const []);
    });
  }
}

/// In-memory admin figures, for tests and for building the screens above them.
class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({
    this.todayValue,
    this.statisticsValue,
    this.attentionValue,
    this.activeUsersValue,
    this.failure,
    String? currentAdminUid,
    Set<String>? platformStaffUids,
    this.customers,
    this.staff,
  })  : currentAdminUid = currentAdminUid ?? 'admin-1',
        platformStaffUids = platformStaffUids ?? {'admin-1'};

  final AdminToday? todayValue;
  final AdminStatistics? statisticsValue;
  final AdminAttention? attentionValue;
  final ActiveUsers? activeUsersValue;
  final Failure? failure;
  final String currentAdminUid;
  final Set<String> platformStaffUids;
  final FakeCustomerRepository? customers;
  final FakeStaffRepository? staff;

  final List<String> deletedAccountCalls = [];

  @override
  Future<Result<AdminAttention>> attention() async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(attentionValue ?? const AdminAttention());
  }

  @override
  Future<Result<AdminToday>> today() async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(todayValue ?? _emptyToday);
  }

  @override
  Future<Result<AdminStatistics>> statistics() async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(statisticsValue ?? _emptyStatistics);
  }

  @override
  Future<Result<void>> deleteAccount(String uid) async {
    if (failure != null) return Result.err(failure!);
    // Platform staff from the shared staff fixture as well as the explicit set, so a
    // platform account seeded in [staff] cannot be deleted here when the server refuses it.
    final isPlatformStaff = platformStaffUids.contains(uid) ||
        (staff?.all.any((m) => m.uid == uid && m.scope == 'platform') ?? false);
    if (uid == currentAdminUid || isPlatformStaff) {
      return const Result.err(PermissionFailure());
    }
    customers?.removeCustomer(uid);
    staff?.removeStaff(uid);
    deletedAccountCalls.add(uid);
    return const Result.ok(null);
  }

  @override
  Future<Result<ActiveUsers>> activeUsers() async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(activeUsersValue ?? const ActiveUsers());
  }

  static final _emptyToday = const AdminToday(
    ordersToday: 0,
    moneyToday: 0,
    needsAttention: [],
    openIssues: 0,
  );

  static final _emptyStatistics = const AdminStatistics(
    customers: 0,
    merchantsByStatus: {},
    ordersTotal: 0,
    avgOrderValue: 0,
    byWeek: [],
    byMonth: [],
  );
}
