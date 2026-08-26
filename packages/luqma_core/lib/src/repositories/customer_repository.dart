import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin.dart';
import '../models/order.dart';
import '../data/column_names.dart';
import '../result.dart';

/// Customers, as AdminApp supports and moderates them.
///
/// Reads go straight through RLS — an admin sees every row. The one write this
/// interface exposes deliberately is not a write at all: [setBlocked] calls a server
/// function, because a flag that decides who may sign in must not be editable by
/// whoever holds the client.
abstract interface class CustomerRepository {
  /// Matches name or phone; an empty query returns the newest accounts.
  Future<Result<List<CustomerSummary>>> search(String query);

  /// One customer's orders, newest first. The admin reads them all through the same
  /// policy the dashboard does.
  Future<Result<List<Order>>> history(String uid);

  /// Blocks or unblocks. Blocked customers fail at sign-in.
  Future<Result<void>> setBlocked(String uid, {required bool blocked});

  /// Gives a customer a new password and returns it, once.
  ///
  /// A customer's account is keyed on a synthetic address with no mailbox and OTP is
  /// off, so "email me a link" and "text me a code" both lead nowhere. Somebody who
  /// forgets their password calls, and the admin reads them what this returns.
  ///
  /// It is never stored: the returned string is the only time it is readable, which is
  /// why it comes back rather than being written anywhere.
  Future<Result<String>> resetPassword(String uid);
}

class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseCustomerRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<List<CustomerSummary>>> search(String query) {
    return Result.guard(() async {
      // Edku is a few thousand people at most: fifty rows answers any search the
      // owner actually types, and keeps the phone list honest about being a page.
      var request = _db.from('users').select();
      final trimmed = query.trim();
      if (trimmed.isNotEmpty) {
        // A phone number typed with spaces still finds its person.
        final digits = trimmed.replaceAll(RegExp(r'[\s-]'), '');
        request = request.or(
          'name.ilike.%$trimmed%,phone.ilike.%${digits.isNotEmpty ? digits : trimmed}%',
        );
      }
      final rows =
          await request.order('created_at', ascending: false).limit(50);
      return rows.map(CustomerSummary.fromRow).toList();
    });
  }

  @override
  Future<Result<List<Order>>> history(String uid) {
    return Result.guard(() async {
      final rows = await _db
          .from('orders')
          .select()
          .eq('customer_uid', uid)
          .order('created_at', ascending: false)
          .limit(50);
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
  Future<Result<String>> resetPassword(String uid) {
    return Result.guard(() async {
      final response = await _db.functions.invoke(
        'reset-customer-password',
        body: {'uid': uid},
      );

      // The function names its refusals so the screen can say which sentence to show.
      switch (response.status) {
        case >= 200 && < 300:
          break;
        case 400:
          // A staff account reached through the customers screen — the staff screen is
          // where those are managed.
          throw const ConflictFailure();
        case 404:
          throw const NotFoundFailure();
        case 401 || 403:
          throw const PermissionFailure();
        default:
          throw UnknownFailure(
            'reset-customer-password: HTTP ${response.status}',
          );
      }

      return (response.data as Map)['password'] as String;
    });
  }
}

/// In-memory customers, for tests and for building screens above it.
class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository({
    List<CustomerSummary> seed = const [],
    Map<String, List<Order>> histories = const {},
    this.failure,
  })  : _customers = {for (final c in seed) c.id: c},
        _histories = Map.of(histories);

  final Map<String, CustomerSummary> _customers;
  final Map<String, List<Order>> _histories;

  /// Makes every call fail with this. Mutable so a test can let a search succeed and
  /// then refuse what follows — which is the shape of most of the interesting cases.
  Failure? failure;

  /// What [setBlocked] did, for assertions.
  final List<(String, bool)> blockCalls = [];

  /// Who [resetPassword] was called for, for assertions.
  final List<String> resetCalls = [];

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
  Future<Result<List<Order>>> history(String uid) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_histories[uid] ?? const []);
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
  Future<Result<String>> resetPassword(String uid) async {
    if (failure != null) return Result.err(failure!);
    if (!_customers.containsKey(uid)) return const Result.err(NotFoundFailure());

    resetCalls.add(uid);
    // Fixed rather than random: a test asserting on a password it cannot predict can
    // only assert that a string came back, which is what the real one guarantees anyway.
    return const Result.ok('demo-pass-42');
  }
}
