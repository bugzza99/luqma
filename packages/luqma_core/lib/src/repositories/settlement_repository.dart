import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../models/settlement.dart';
import '../result.dart';

/// A merchant's statement: what the platform took, order by order.
///
/// Read-only, and there is no write method here on purpose. Nothing in the product may
/// write this table from a client — the policy grants `select` and nothing else, and the
/// only thing that inserts a row is the settlement trigger running as its definer. A
/// repository with a `save` would be an interface promising something the database
/// refuses, which is how a screen comes to show a button that cannot work.
abstract interface class SettlementRepository {
  /// The merchant's settlements, newest first.
  ///
  /// [limit] because a statement screen shows a page, not a year. The policy already
  /// restricts this to the merchant's own rows (or an admin's view of anybody's), so the
  /// merchant id here narrows a query rather than granting anything.
  Future<Result<List<OrderSettlement>>> forMerchant(
    String merchantId, {
    int limit,
  });

  /// The cash collected against this merchant's commission, newest first.
  Future<Result<List<CommissionPayment>>> paymentsFor(
    String merchantId, {
    int limit,
  });

  /// Records a collection and returns what is still owed afterwards.
  ///
  /// The remaining balance comes back from the same statement that wrote it rather than
  /// being re-read: a second fetch could race a delivery settling, and the figure an
  /// admin is shown immediately after taking cash must be the one their own act produced.
  ///
  /// Not capped at what is owed. An admin standing in a shop takes what is handed over,
  /// and a merchant who rounds up must not meet an error with the cash on the counter —
  /// the balance goes negative, which is credit the next delivery eats into.
  Future<Result<int>> recordPayment({
    required String merchantId,
    required int amount,
    String? note,
  });
}

class SupabaseSettlementRepository implements SettlementRepository {
  SupabaseSettlementRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<List<OrderSettlement>>> forMerchant(
    String merchantId, {
    int limit = 100,
  }) {
    return Result.guard(() async {
      final rows = await _db
          .from('order_settlements')
          .select()
          .eq('merchant_id', merchantId)
          // Newest first, spelled out. `order()` in this SDK defaults to descending,
          // which happens to be what this wants — and the flag is passed anyway, because
          // a reader should not have to know that to see the intent, and the one query in
          // this package that leaned on the default was wrong for a month.
          .order('settled_at', ascending: false)
          .limit(limit);

      return [
        for (final row in rows)
          OrderSettlement.fromJson(ColumnNames.toModel(row)),
      ];
    });
  }

  @override
  Future<Result<List<CommissionPayment>>> paymentsFor(
    String merchantId, {
    int limit = 100,
  }) {
    return Result.guard(() async {
      final rows = await _db
          .from('commission_payments')
          .select()
          .eq('merchant_id', merchantId)
          .order('recorded_at', ascending: false)
          .limit(limit);

      return [
        for (final row in rows)
          CommissionPayment.fromJson(ColumnNames.toModel(row)),
      ];
    });
  }

  @override
  Future<Result<int>> recordPayment({
    required String merchantId,
    required int amount,
    String? note,
  }) {
    return Result.guard(() async {
      // An RPC rather than two writes: the receipt and the balance move together or
      // neither does, and a client that could do one without the other could produce a
      // receipt for money the account says was never paid.
      final result = await _db.rpc<Map<String, dynamic>>(
        'record_commission_payment',
        params: {
          'p_merchant_id': merchantId,
          'p_amount': amount,
          'p_note': note,
        },
      );
      return result['remaining'] as int;
    });
  }
}

/// Holds settlements in memory, for the screens and their tests.
class FakeSettlementRepository implements SettlementRepository {
  FakeSettlementRepository({
    List<OrderSettlement> seed = const [],
    List<CommissionPayment> payments = const [],
    this.failure,
    this.writeFailure,
    this.owedStart = 0,
  })  : _settlements = List.of(seed),
        _payments = List.of(payments),
        _owed = owedStart;

  final List<OrderSettlement> _settlements;
  final List<CommissionPayment> _payments;

  /// When set, every call fails with this.
  final Failure? failure;

  /// Fails only [recordPayment]. A card that could not load offers no button at all, so
  /// a screen whose *collection* is refused is a different situation from one whose
  /// figures never arrived — and only the first can be tested by pressing anything.
  final Failure? writeFailure;

  /// What the merchant owed before any collection recorded here.
  final int owedStart;
  int _owed;

  /// What is owed now, so a test can assert a collection actually moved it.
  int get owed => _owed;

  /// Everything recorded through [recordPayment].
  List<CommissionPayment> get recorded => List.unmodifiable(_payments);

  @override
  Future<Result<List<OrderSettlement>>> forMerchant(
    String merchantId, {
    int limit = 100,
  }) async {
    if (failure != null) return Result.err(failure!);

    // The same filter and the same order as the real query, because a fake that returns
    // a differently-sorted list lets a screen pass a test and show yesterday's charge at
    // the top in the street.
    final mine = _settlements.where((s) => s.merchantId == merchantId).toList()
      ..sort((a, b) => (b.settledAt ?? DateTime(0))
          .compareTo(a.settledAt ?? DateTime(0)));
    return Result.ok(mine.take(limit).toList());
  }

  @override
  Future<Result<List<CommissionPayment>>> paymentsFor(
    String merchantId, {
    int limit = 100,
  }) async {
    if (failure != null) return Result.err(failure!);

    final mine = _payments.where((p) => p.merchantId == merchantId).toList()
      ..sort((a, b) => (b.recordedAt ?? DateTime(0))
          .compareTo(a.recordedAt ?? DateTime(0)));
    return Result.ok(mine.take(limit).toList());
  }

  @override
  Future<Result<int>> recordPayment({
    required String merchantId,
    required int amount,
    String? note,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (writeFailure != null) return Result.err(writeFailure!);
    // The same refusal the database makes, so a screen cannot pass a test against a
    // fake that accepts what production rejects.
    if (amount <= 0) return const Result.err(ConflictFailure());

    _payments.add(CommissionPayment(
      id: 'pay-${_payments.length + 1}',
      merchantId: merchantId,
      amount: amount,
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
      recordedBy: 'admin1',
      recordedAt: DateTime(2026, 8, 30),
    ));
    _owed -= amount;
    return Result.ok(_owed);
  }
}
