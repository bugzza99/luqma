import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/billing.dart';
import '../result.dart';

/// Plans, subscriptions, and the cash that pays for them.
///
/// Every figure here is money that changed hands in a shop, so nothing is inferred. A
/// subscription exists because somebody recorded a payment; a wallet has credit because
/// somebody handed over notes. Both leave an entry naming who wrote them down — without
/// that, a disputed payment has nobody to ask.
abstract interface class BillingRepository {
  /// The plans on offer, in the order the admin set.
  Future<Result<List<Plan>>> plans({bool includeInactive});

  /// The merchant's most recent term, expired or not. Live.
  Stream<Subscription?> watchSubscription(String merchantId);

  /// Takes a payment. Extends an unexpired term rather than restarting it — the
  /// alternative is a merchant losing days they already paid for.
  Future<Result<Subscription>> recordPayment({
    required String merchantId,
    required String planId,
    required int amount,
    required int months,
    required String recordedBy,
  });

  /// Adds prepaid credit. Adds to the balance; never replaces it.
  Future<Result<void>> topUpWallet({
    required String merchantId,
    required int amount,
    required String recordedBy,
  });
}

class SupabaseBillingRepository implements BillingRepository {
  SupabaseBillingRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<List<Plan>>> plans({bool includeInactive = false}) {
    return Result.guard(() async {
      // `ascending` spelled out, as everywhere: the default is false.
      final rows =
          await _db.from('plans').select().order('sort_order', ascending: true);
      return rows
          .map((row) => Plan.fromJson(ColumnNames.toModel(row)))
          .where((plan) => includeInactive || plan.isActive)
          .toList();
    });
  }

  @override
  Stream<Subscription?> watchSubscription(String merchantId) {
    return watchRows(
      db: _db,
      table: 'subscriptions',
      map: _toSubscription,
      filters: [RowFilter('merchant_id', merchantId)],
      // Newest expiry first; the caller takes the first.
      orderBy: 'expires_at',
      ascending: false,
    ).map((terms) => terms.isEmpty ? null : terms.first);
  }

  @override
  Future<Result<Subscription>> recordPayment({
    required String merchantId,
    required String planId,
    required int amount,
    required int months,
    required String recordedBy,
  }) {
    return Result.guard(() async {
      final row = await _db.rpc('record_subscription_payment', params: {
        'p_merchant_id': merchantId,
        'p_plan_id': planId,
        'p_amount': amount,
        'p_months': months,
        'p_recorded_by': recordedBy,
      });
      return _toSubscription(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<Result<void>> topUpWallet({
    required String merchantId,
    required int amount,
    required String recordedBy,
  }) {
    return Result.guard(
      () => _db.rpc('top_up_wallet', params: {
        'p_merchant_id': merchantId,
        'p_amount': amount,
        'p_recorded_by': recordedBy,
      }),
    );
  }

  Subscription _toSubscription(Map<String, dynamic> row) =>
      Subscription.fromJson(ColumnNames.toModel(row));
}

/// A month, for billing purposes.
///
/// Thirty days rather than a calendar month, deliberately: a merchant who pays on the
/// 31st and a merchant who pays on the 1st should get the same number of days, and
/// nobody in a shop is going to argue about the difference in their favour.
const _daysPerMonth = 30;

/// In-memory billing, for tests and for the screens above it.
class FakeBillingRepository implements BillingRepository {
  FakeBillingRepository({
    List<Plan> seedPlans = const [],
    List<Subscription> seedSubscriptions = const [],
    Map<String, int> wallets = const {},
    this.failure,
  })  : _plans = List.of(seedPlans),
        _subscriptions = {for (final s in seedSubscriptions) s.id: s},
        _wallets = Map.of(wallets);

  final List<Plan> _plans;
  final Map<String, Subscription> _subscriptions;
  final Map<String, int> _wallets;
  final Failure? failure;

  final _changed = StreamController<void>.broadcast();

  /// Every payment and top-up recorded, so a test can assert on what a screen produced.
  final List<Map<String, Object?>> audit = [];

  int walletOf(String merchantId) => _wallets[merchantId] ?? 0;

  /// The merchant's latest term, read synchronously.
  ///
  /// A widget test runs on a fake clock and cannot await the stream above — the future
  /// simply never completes — so this is what lets a test assert on what a screen wrote.
  Subscription? subscriptionOf(String merchantId) {
    final terms = _subscriptions.values
        .where((s) => s.merchantId == merchantId)
        .toList()
      ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
    return terms.firstOrNull;
  }

  Stream<T> _live<T>(T Function() read) => Stream.multi((listener) {
        listener.add(read());
        final sub = _changed.stream.listen((_) => listener.add(read()));
        listener.onCancel = sub.cancel;
      });

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() => _changed.close();

  @override
  Future<Result<List<Plan>>> plans({bool includeInactive = false}) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(
      _plans.where((p) => includeInactive || p.isActive).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
    );
  }

  @override
  Stream<Subscription?> watchSubscription(String merchantId) {
    if (failure != null) return Stream.error(failure!);
    return _live(() {
      final terms = _subscriptions.values
          .where((s) => s.merchantId == merchantId)
          .toList()
        ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
      return terms.firstOrNull;
    });
  }

  @override
  Future<Result<Subscription>> recordPayment({
    required String merchantId,
    required String planId,
    required int amount,
    required int months,
    required String recordedBy,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (months < 1 || amount < 0) return const Result.err(ConflictFailure());

    final now = DateTime.now();
    // Read synchronously, not by awaiting this fake's own stream: under a widget test's
    // fake clock that future never completes, and the screen calling this would hang.
    final existing = subscriptionOf(merchantId);
    final from =
        existing != null && existing.isActiveAt(now) ? existing.expiresAt : now;

    final subscription = Subscription(
      id: 'sub-${_subscriptions.length + 1}',
      merchantId: merchantId,
      planId: planId,
      amount: amount,
      startedAt: now,
      expiresAt: from.add(Duration(days: _daysPerMonth * months)),
      recordedBy: recordedBy,
    );

    _subscriptions[subscription.id] = subscription;
    audit.add({
      'action': 'recordSubscriptionPayment',
      'by': recordedBy,
      'merchantId': merchantId,
      'planId': planId,
      'amount': amount,
      'months': months,
    });
    _notify();
    return Result.ok(subscription);
  }

  @override
  Future<Result<void>> topUpWallet({
    required String merchantId,
    required int amount,
    required String recordedBy,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (amount <= 0) return const Result.err(ConflictFailure());

    _wallets[merchantId] = walletOf(merchantId) + amount;
    audit.add({
      'action': 'topUpWallet',
      'by': recordedBy,
      'merchantId': merchantId,
      'amount': amount,
    });
    _notify();
    return const Result.ok(null);
  }
}