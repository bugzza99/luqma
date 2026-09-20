import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/courier_money.dart';
import '../result.dart';

/// كشف حساب المندوب — what was charged on each delivery, and what has been paid.
///
/// The courier's own side and the admin's are the same rows read through the same
/// policies: `courier_settlements` and `courier_commission_payments` both allow
/// `courier_uid = auth.uid() or is_admin()`. So a rider checking their account and the
/// owner collecting against it are looking at one ledger, which is the only way the
/// conversation at the end of the week can end.
///
/// There is no write here but the collection, and that is an RPC: a receipt and a balance
/// move together or neither does, and a client that could do one without the other could
/// produce paper saying money changed hands while the account says otherwise.
abstract interface class CourierStatementRepository {
  /// Every delivery that was settled, newest first.
  ///
  /// [courierUid] null means the signed-in courier — the policy answers it, so a rider
  /// never has to name themselves and cannot name anybody else.
  Future<Result<List<CourierCharge>>> charges({String? courierUid, int limit});

  /// Cash handed over, newest first.
  Future<Result<List<CourierPayment>>> payments({String? courierUid, int limit});

  /// What one courier owes right now. Null is the signed-in rider.
  ///
  /// Nullable for the same reason [charges] is: a screen that has to know its own uid
  /// first has to wait for the identity to resolve, and something has to be drawn in the
  /// meantime. That something was a spinner the page could get stuck behind.
  Future<Result<int>> owedBy(String? courierUid);

  /// Every courier with an account that is not square, for the owner's collection round.
  ///
  /// Includes credits — somebody who has overpaid is somebody the owner owes, and a list
  /// that quietly drops them is a list that loses money in the other direction.
  Future<Result<List<CourierBalance>>> outstanding();

  /// Records cash collected from a courier and lowers their balance in one statement.
  ///
  /// [receiptId] names the attempt, so a retry after a lost reply returns the first
  /// answer instead of collecting twice.
  Future<Result<CourierCollection>> recordPayment({
    required String courierUid,
    required int amount,
    String? note,
    String? receiptId,
  });
}

class SupabaseCourierStatementRepository implements CourierStatementRepository {
  SupabaseCourierStatementRepository(this._db);

  final SupabaseClient _db;

  /// The order behind a charge, for a line somebody can recognise. Embedded rather than
  /// fetched per row: a hundred lines would be a hundred round trips on a phone in the
  /// street.
  static const _columns =
      'order_id, courier_uid, basis, bps, amount, ground, settled_at, reversed_at, '
      'orders(order_number, merchant_name)';

  @override
  Future<Result<List<CourierCharge>>> charges({
    String? courierUid,
    int limit = 100,
  }) {
    return Result.guard(() async {
      var query = _db.from('courier_settlements').select(_columns);
      // No filter for a rider: the policy already narrows it to their own, and a client
      // that names itself is a client that could name somebody else.
      if (courierUid != null) query = query.eq('courier_uid', courierUid);

      // Spelled out, because postgrest-dart's `order()` defaults to descending and the
      // one query in this package that leaned on that default was wrong for a month.
      final rows = await query.order('settled_at', ascending: false).limit(limit);
      return [for (final row in rows) CourierCharge.fromRow(row)];
    });
  }

  @override
  Future<Result<List<CourierPayment>>> payments({
    String? courierUid,
    int limit = 100,
  }) {
    return Result.guard(() async {
      var query = _db.from('courier_commission_payments').select();
      if (courierUid != null) query = query.eq('courier_uid', courierUid);

      final rows = await query.order('created_at', ascending: false).limit(limit);
      return [for (final row in rows) CourierPayment.fromRow(row)];
    });
  }

  @override
  Future<Result<int>> owedBy(String? courierUid) {
    return Result.guard(() async {
      var query = _db.from('staff').select('commission_owed');
      // `read_staff` already narrows an unfiltered read to the caller's own row, so a
      // rider asking about themselves does not have to name themselves.
      if (courierUid != null) query = query.eq('uid', courierUid);
      final row = await query.maybeSingle();
      return (row?['commission_owed'] as num?)?.toInt() ?? 0;
    });
  }

  @override
  Future<Result<List<CourierBalance>>> outstanding() {
    return Result.guard(() async {
      final rows = await _db
          .from('staff')
          .select('uid, name, phone, commission_owed, is_active')
          .eq('role', 'courier')
          .neq('commission_owed', 0)
          // Biggest debt first: that is the call the owner makes next.
          .order('commission_owed', ascending: false);
      return [for (final row in rows) CourierBalance.fromRow(row)];
    });
  }

  @override
  Future<Result<CourierCollection>> recordPayment({
    required String courierUid,
    required int amount,
    String? note,
    String? receiptId,
  }) {
    return Result.guard(() async {
      final result = await _db.rpc<Map<String, dynamic>>(
        'record_courier_payment',
        params: {
          'p_courier_uid': courierUid,
          'p_amount': amount,
          'p_note': note,
          'p_receipt_id': receiptId,
        },
      );
      // What the server says is left, never what this screen computed. A reply that does
      // not say is a reply this screen must not put a number on.
      final remaining = result['remaining'];
      if (remaining is! num) throw const UnknownFailure('no balance in the reply');
      return CourierCollection(remaining: remaining.toInt());
    });
  }
}

/// An in-memory ledger, for the screens and their tests.
///
/// It keeps the one rule that matters: a payment moves the balance and files a receipt,
/// or it does neither. A fake that let those drift apart would let a screen be written
/// against an account the server can never produce.
class FakeCourierStatementRepository implements CourierStatementRepository {
  FakeCourierStatementRepository({
    List<CourierCharge>? charges,
    List<CourierPayment>? payments,
    Map<String, int>? owed,
    List<CourierBalance>? balances,
    this.failure,
  })  : _charges = [...?charges],
        _payments = [...?payments],
        _owed = {...?owed},
        _balances = [...?balances];

  final List<CourierCharge> _charges;
  final List<CourierPayment> _payments;
  final Map<String, int> _owed;
  final List<CourierBalance> _balances;

  Failure? failure;

  /// Receipt ids already honoured, so a retry returns the first answer.
  final Map<String, CourierCollection> _receipts = {};

  final List<({String courierUid, int amount})> recorded = [];

  @override
  Future<Result<List<CourierCharge>>> charges({
    String? courierUid,
    int limit = 100,
  }) async {
    if (failure case final f?) return Result.err(f);
    return Result.ok(_charges.take(limit).toList());
  }

  @override
  Future<Result<List<CourierPayment>>> payments({
    String? courierUid,
    int limit = 100,
  }) async {
    if (failure case final f?) return Result.err(f);
    return Result.ok(_payments.take(limit).toList());
  }

  @override
  Future<Result<int>> owedBy(String? courierUid) async {
    if (failure case final f?) return Result.err(f);
    if (courierUid != null) return Result.ok(_owed[courierUid] ?? 0);
    // Whoever the single seeded balance belongs to: the fake has one rider in it, the
    // way a signed-in rider has one account.
    return Result.ok(_owed.values.isEmpty ? 0 : _owed.values.first);
  }

  @override
  Future<Result<List<CourierBalance>>> outstanding() async {
    if (failure case final f?) return Result.err(f);
    return Result.ok(_balances);
  }

  @override
  Future<Result<CourierCollection>> recordPayment({
    required String courierUid,
    required int amount,
    String? note,
    String? receiptId,
  }) async {
    if (failure case final f?) return Result.err(f);

    if (receiptId != null) {
      final stored = _receipts[receiptId];
      if (stored != null) return Result.ok(stored);
    }

    final remaining = (_owed[courierUid] ?? 0) - amount;
    _owed[courierUid] = remaining;
    _payments.insert(
      0,
      CourierPayment(
        id: 'p${_payments.length + 1}',
        amount: amount,
        createdAt: DateTime.now(),
        note: note,
      ),
    );
    recorded.add((courierUid: courierUid, amount: amount));

    final result = CourierCollection(remaining: remaining);
    if (receiptId != null) _receipts[receiptId] = result;
    return Result.ok(result);
  }
}
