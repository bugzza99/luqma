import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin.dart';
import '../models/order.dart';
import '../data/column_names.dart';
import '../result.dart';
import '../util/phone.dart';
import 'staff_repository.dart';

/// Customers, as AdminApp supports and moderates them.
///
/// Reads go straight through RLS — an admin sees every row. The one write this
/// interface exposes deliberately is not a write at all: [setBlocked] calls a server
/// function, because a flag that decides who may sign in must not be editable by
/// whoever holds the client.
/// How many orders one page of a customer's history holds.
const historyPage = 50;

abstract interface class CustomerRepository {
  /// Matches name or phone; an empty query returns the newest accounts.
  Future<Result<List<CustomerSummary>>> search(String query);

  /// One customer's orders, newest first, [historyPage] at a time. The admin reads them
  /// all through the same policy the dashboard does. [after] is the last order already
  /// shown, and asks for the page older than it — a support call about a months-old order
  /// used to stop at the newest fifty (QA review 2026-09-19). The cursor is the time *and*
  /// the id: two orders placed in the same instant at a page boundary would otherwise
  /// lose one of them for good.
  Future<Result<List<Order>>> history(String uid, {Order? after});

  /// Blocks or unblocks. Blocked customers fail at sign-in.
  Future<Result<void>> setBlocked(String uid, {required bool blocked});

  /// Sets a new password chosen by the admin for a customer or merchant staff member.
  Future<Result<void>> setPassword(String uid, String password);
}

class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseCustomerRepository(this._db);

  final SupabaseClient _db;

  /// A value PostgREST reads as one value inside `or(...)`: double-quoted, with the two
  /// characters that mean something inside the quotes escaped.
  static String _quoted(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  @override
  Future<Result<List<CustomerSummary>>> search(String query) {
    return Result.guard(() async {
      // Edku is a few thousand people at most: fifty rows answers any search the
      // owner actually types, and keeps the phone list honest about being a page.
      var request = _db.from('users').select();
      final trimmed = query.trim();
      if (trimmed.isNotEmpty) {
        // `Phone.normalize`, which is the same folding sign-up does before it stores the
        // number — not a local copy that only strips spaces.
        //
        // Sign-up writes `010…` whatever was typed, so an admin on an Arabic keyboard
        // searching `٠١٠…` was looking for a spelling that is never stored. They found
        // nobody and told the customer on the phone that they have no account — and this
        // screen is the *only* way back from a forgotten password, because there is no
        // mailbox and no SMS.
        final digits = Phone.normalize(trimmed);
        // Quoted, because the text goes into a PostgREST `or(...)` where a comma or a
        // bracket is syntax: a name with one in it made the whole filter invalid, and the
        // screen showed an error instead of the person (D12).
        request = request.or(
          'name.ilike.${_quoted('%$trimmed%')},'
          'phone.ilike.${_quoted('%${digits.isNotEmpty ? digits : trimmed}%')}',
        );
      }
      final rows =
          await request.order('created_at', ascending: false).limit(50);
      return rows.map(CustomerSummary.fromRow).toList();
    });
  }

  @override
  Future<Result<List<Order>>> history(String uid, {Order? after}) {
    return Result.guard(() async {
      var request = _db.from('orders').select().eq('customer_uid', uid);
      final at = after?.placedAt?.toUtc().toIso8601String();
      if (after != null && at != null) {
        request = request.or(
          'placed_at.lt.$at,and(placed_at.eq.$at,id.lt.${after.id})',
        );
      }
      // `placed_at` then `id`, the same order the cursor reads — `orders_customer_idx`
      // covers the first.
      final rows = await request
          .order('placed_at', ascending: false)
          .order('id', ascending: false)
          .limit(historyPage);
      return rows.map(_toOrder).toList();
    });
  }

  Order _toOrder(Map<String, dynamic> row) {
    final model = ColumnNames.toModel(row);
    for (final key in ['placedAt', 'acceptDeadlineAt', 'deliveredAt']) {
      if (model[key] is String) {
        model[key] = DateTime.parse(model[key] as String).toLocal();
      }
    }
    return Order.fromJson(model);
  }

  @override
  Future<Result<void>> setBlocked(String uid, {required bool blocked}) {
    return Result.guard(
      () => _db.rpc('admin_set_customer_blocked', params: {
        'p_uid': uid,
        'p_blocked': blocked,
      }),
    );
  }

  @override
  Future<Result<void>> setPassword(String uid, String password) {
    return Result.guard(() async {
      int status;
      dynamic data;
      try {
        final response = await _db.functions.invoke(
          'reset-customer-password',
          body: {'uid': uid, 'password': password},
        );
        status = response.status;
        data = response.data;
      } on FunctionException catch (e) {
        status = e.status;
        data = e.details;
      }

      if (status >= 200 && status < 300) {
        return;
      }

      final error = data is Map ? data['error'] as String? : null;
      if (status == 400) {
        if (error == 'badPassword') throw const ValidationFailure();
        if (error == 'notAllowed') throw const PermissionFailure();
        throw const ValidationFailure();
      }
      if (status == 404) {
        throw const NotFoundFailure();
      }
      if (status == 401 || status == 403) {
        throw const PermissionFailure();
      }
      throw UnknownFailure('reset-customer-password: HTTP $status');
    });
  }
}

/// In-memory customers, for tests and for building screens above it.
class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository({
    List<CustomerSummary> seed = const [],
    Map<String, List<Order>> histories = const {},
    this.failure,
    this.staff,
  })  : _customers = {for (final c in seed) c.id: c},
        _histories = Map.of(histories);

  final Map<String, CustomerSummary> _customers;
  final Map<String, List<Order>> _histories;

  /// Staff accounts, so [setPassword] refuses platform staff and accepts shop staff the
  /// way `reset-customer-password` does.
  final FakeStaffRepository? staff;

  /// Makes every call fail with this. Mutable so a test can let a search succeed and
  /// then refuse what follows — which is the shape of most of the interesting cases.
  Failure? failure;

  /// What [setBlocked] did, for assertions.
  final List<(String, bool)> blockCalls = [];

  /// Who [setPassword] was called for, for assertions.
  final List<(String, String)> passwordCalls = [];

  /// Legacy getter for assertions checking callers by uid.
  List<String> get resetCalls => passwordCalls.map((c) => c.$1).toList();

  /// Removes a customer by uid, used by account deletion.
  void removeCustomer(String uid) {
    _customers.remove(uid);
  }

  @override
  Future<Result<List<CustomerSummary>>> search(String query) async {
    if (failure != null) return Result.err(failure!);
    // Same normalization as the Supabase implementation: a number typed with
    // spaces still finds its person.
    final trimmed = query.trim();
    final digits = trimmed.replaceAll(RegExp(r'[\s-]'), '');
    return Result.ok(_customers.values.where((c) {
      if (trimmed.isEmpty) return true;
      return c.name.contains(trimmed) || c.phone.contains(digits);
    }).toList());
  }

  @override
  Future<Result<List<Order>>> history(String uid, {Order? after}) async {
    if (failure != null) return Result.err(failure!);
    // Seeded newest first, as the server answers; the page starts after [after].
    final all = _histories[uid] ?? const <Order>[];
    final start = after == null ? 0 : all.indexWhere((o) => o.id == after.id) + 1;
    return Result.ok(all.skip(start).take(historyPage).toList());
  }

  @override
  Future<Result<void>> setBlocked(String uid, {required bool blocked}) async {
    if (failure != null) return Result.err(failure!);
    final existing = _customers[uid];
    if (existing == null) return const Result.err(NotFoundFailure());
    _customers[uid] = CustomerSummary(
      id: existing.id,
      name: existing.name,
      phone: existing.phone,
      isBlocked: blocked,
      rejectedOrdersCount: existing.rejectedOrdersCount,
      createdAt: existing.createdAt,
    );
    blockCalls.add((uid, blocked));
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setPassword(String uid, String password) async {
    if (failure != null) return Result.err(failure!);
    final trimmed = password.trim();
    if (trimmed.length < 8 || trimmed.length > 72) {
      return const Result.err(ValidationFailure());
    }
    final member = staff?.all.where((m) => m.uid == uid).firstOrNull;
    if (member != null) {
      if (member.scope != 'merchant') return const Result.err(PermissionFailure());
    } else if (!_customers.containsKey(uid)) {
      return const Result.err(NotFoundFailure());
    }

    passwordCalls.add((uid, password));
    return const Result.ok(null);
  }
}
