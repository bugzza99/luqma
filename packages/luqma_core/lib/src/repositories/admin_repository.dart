import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin.dart';
import '../models/order.dart' show OrderStatus;
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

  /// Cancels an order nobody answered, from «اليوم»'s queue — as staff, with the reason
  /// and the person written into the audit log.
  ///
  /// Not [OrderRepository.cancel]: that is the customer's own, which matches only `placed`
  /// and signs the cancellation as the customer. The queue is `needsAttention` orders, so
  /// it matched none of them. [ConflictFailure] when the order moved while the sheet was
  /// open — a kitchen that has started is food somebody cooked.
  Future<Result<void>> cancelUnansweredOrder(String orderId, {required String reason});
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

  @override
  Future<Result<void>> cancelUnansweredOrder(String orderId, {required String reason}) {
    return Result.guard(
      () => _db.rpc('admin_cancel_order', params: {
        'p_order_id': orderId,
        'p_reason': reason,
      }),
    );
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
    Map<String, OrderStatus> orderStatuses = const {},
  })  : currentAdminUid = currentAdminUid ?? 'admin-1',
        platformStaffUids = platformStaffUids ?? {'admin-1'},
        // Every order in the queue is `needsAttention`, because that is what the queue is;
        // [orderStatuses] adds orders elsewhere in their lives, or moves one on.
        _orderStatuses = {
          for (final item in todayValue?.needsAttention ?? const <NeedsAttentionItem>[])
            item.id: OrderStatus.needsAttention,
          ...orderStatuses,
        };

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

  final Map<String, OrderStatus> _orderStatuses;

  /// Every order cancelled from the queue, with the reason it was given.
  final Map<String, String> cancelledOrders = {};

  @override
  Future<Result<AdminAttention>> attention() async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(attentionValue ?? const AdminAttention());
  }

  @override
  Future<Result<AdminToday>> today() async {
    if (failure != null) return Result.err(failure!);
    final today = todayValue ?? _emptyToday;
    // An order cancelled from the queue leaves it, as it does on the server.
    return Result.ok(AdminToday(
      ordersToday: today.ordersToday,
      moneyToday: today.moneyToday,
      platformToday: today.platformToday,
      needsAttention: [
        for (final item in today.needsAttention)
          if (_orderStatuses[item.id] == OrderStatus.needsAttention) item,
      ],
      openIssues: today.openIssues,
    ));
  }

  /// The server's four answers: no reason, no order, an order that has moved on, or done.
  @override
  Future<Result<void>> cancelUnansweredOrder(String orderId, {required String reason}) async {
    if (failure != null) return Result.err(failure!);
    if (reason.trim().isEmpty) return const Result.err(ValidationFailure());
    final status = _orderStatuses[orderId];
    if (status == null) return const Result.err(NotFoundFailure());
    if (status != OrderStatus.placed && status != OrderStatus.needsAttention) {
      return const Result.err(ConflictFailure());
    }
    _orderStatuses[orderId] = OrderStatus.cancelled;
    cancelledOrders[orderId] = reason.trim();
    return const Result.ok(null);
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
