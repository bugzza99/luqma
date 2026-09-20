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
/// What a collection actually recorded, as the server holds it.
///
/// [recorded] is not "the amount that was asked for". A retry after a lost reply carries
/// the receipt id of the attempt that may already have landed, and the server answers
/// with that first receipt — so the two can differ, and when they do the one on the
/// screen has to be the server's. Confirming «اتسجّل 200» over a receipt that says 100 is
/// a false receipt in a cash business, which is the one thing this whole idempotency
/// path exists to prevent.
class CommissionCollection {
  const CommissionCollection({required this.recorded, required this.remaining});

  /// The amount on the receipt, in piastres.
  final int recorded;

  /// What the merchant still owes after it, in piastres. Negative is credit.
  final int remaining;

  /// True when the server answered with a receipt for a different amount than the one
  /// this attempt asked for — meaning this is a retry of a collection that had already
  /// landed, and the figure typed the second time was never recorded.
  bool matches(int requested) => recorded == requested;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommissionCollection &&
          runtimeType == other.runtimeType &&
          recorded == other.recorded &&
          remaining == other.remaining;

  @override
  int get hashCode => Object.hash(recorded, remaining);

  @override
  String toString() =>
      'CommissionCollection(recorded: $recorded, remaining: $remaining)';
}

abstract interface class SettlementRepository {
  /// Complete account totals, not the sum of either bounded list.
  Future<Result<SettlementSummary>> summaryFor(String merchantId);

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
  ///
  /// The receipt comes back as well as the balance, because on a retry the two can
  /// disagree with what was asked for: see [CommissionCollection].
  Future<Result<CommissionCollection>> recordPayment({
    required String merchantId,
    required int amount,
    String? note,

    /// Names this attempt, so a retry after a lost reply returns the original receipt
    /// instead of collecting the cash a second time. The screen makes one per press and
    /// keeps it across retries; null is the old behaviour and still accepted, because an
    /// APK already on a phone cannot learn a new argument.
    String? clientPaymentId,
  });
}

class SupabaseSettlementRepository implements SettlementRepository {
  SupabaseSettlementRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<SettlementSummary>> summaryFor(String merchantId) =>
      Result.guard(() async {
        final row = await _db.rpc<Map<String, dynamic>?>(
          'settlement_summary',
          params: {'p_merchant_id': merchantId},
        );
        if (row == null) throw const PermissionFailure();
        return SettlementSummary(
          orders: row['orders'] as int,
          taken: row['taken'] as int,
          platformOwes: row['platform_owes'] as int,
          paid: row['paid'] as int,
        );
      });

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
  Future<Result<CommissionCollection>> recordPayment({
    required String merchantId,
    required int amount,
    String? note,

    /// Names this attempt, so a retry after a lost reply returns the original receipt
    /// instead of collecting the cash a second time. The screen makes one per press and
    /// keeps it across retries; null is the old behaviour and still accepted, because an
    /// APK already on a phone cannot learn a new argument.
    String? clientPaymentId,
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
          'p_client_payment_id': clientPaymentId,
        },
      );
      // The receipt the server holds, which on a retry is the *first* attempt's — not
      // this one's. The amount asked for is deliberately not the fallback for a missing
      // figure either: a reply that does not say what was recorded is a reply this
      // screen must not put a number on.
      final payment = result['payment'];
      final recorded = payment is Map ? payment['amount'] as int? : null;
      if (recorded == null) throw const UnknownFailure('no receipt in the reply');

      return CommissionCollection(
        recorded: recorded,
        remaining: result['remaining'] as int,
      );
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
        _owed = owedStart {
    // A seeded receipt is a receipt the server holds. `_byReceipt` used to be built only
    // by [recordPayment], so a fake seeded with a payment that already carried a
    // `clientPaymentId` took the money a *second* time for that id — where
    // `record_commission_payment` returns the receipt it already has and moves nothing.
    // A fake more permissive than the database is how a screen is proved right against a
    // server that contradicts it, which is the finding behind half this file's comments.
    for (final p in payments) {
      final id = p.clientPaymentId;
      if (id != null) _byReceipt['${p.merchantId}/$id'] = p;
    }
  }

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
  Future<Result<SettlementSummary>> summaryFor(String merchantId) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(SettlementSummary.of(
      _settlements.where((s) => s.merchantId == merchantId),
      payments: _payments.where((p) => p.merchantId == merchantId),
    ));
  }

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

  /// The receipt each attempt wrote, keyed the way the unique index is.
  final Map<String, CommissionPayment> _byReceipt = {};

  @override
  Future<Result<CommissionCollection>> recordPayment({
    required String merchantId,
    required int amount,
    String? note,

    /// Names this attempt, so a retry after a lost reply returns the original receipt
    /// instead of collecting the cash a second time. The screen makes one per press and
    /// keeps it across retries; null is the old behaviour and still accepted, because an
    /// APK already on a phone cannot learn a new argument.
    String? clientPaymentId,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (writeFailure != null) return Result.err(writeFailure!);
    // The same refusal the database makes, so a screen cannot pass a test against a
    // fake that accepts what production rejects.
    if (amount <= 0) return const Result.err(ConflictFailure());

    // And the same idempotency. `record_commission_payment` returns the receipt the
    // first attempt wrote, whatever the retry asks for — a fake that happily took the
    // money twice is a fake no screen could be proved right against, which is precisely
    // how a retry came to be able to confirm an amount nobody had recorded.
    final key = clientPaymentId == null ? null : '$merchantId/$clientPaymentId';
    final already = key == null ? null : _byReceipt[key];
    if (already != null) {
      return Result.ok(
        CommissionCollection(recorded: already.amount, remaining: _owed),
      );
    }

    final payment = CommissionPayment(
      id: 'pay-${_payments.length + 1}',
      merchantId: merchantId,
      amount: amount,
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
      recordedBy: 'admin1',
      recordedAt: DateTime(2026, 8, 30),
      // The column the server stores as well, so a screen asking the receipts whether a
      // pending attempt landed gets the same answer here as it would in the street.
      clientPaymentId: clientPaymentId,
    );
    _payments.add(payment);
    if (key != null) _byReceipt[key] = payment;
    _owed -= amount;
    return Result.ok(CommissionCollection(recorded: amount, remaining: _owed));
  }
}
