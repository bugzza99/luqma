import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin.dart';
import '../result.dart';

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
}

/// In-memory admin figures, for tests and for building the screens above them.
class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({this.todayValue, this.statisticsValue, this.failure});

  final AdminToday? todayValue;
  final AdminStatistics? statisticsValue;
  final Failure? failure;

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
