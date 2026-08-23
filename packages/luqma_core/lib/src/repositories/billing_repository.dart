import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

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

/// A month, for billing purposes.
///
/// Thirty days rather than a calendar month, deliberately: a merchant who pays on the
/// 31st and a merchant who pays on the 1st should get the same number of days, and
/// nobody in a shop is going to argue about the difference in their favour.
const _daysPerMonth = 30;

class FirestoreBillingRepository implements BillingRepository {
  FirestoreBillingRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<List<Plan>>> plans({bool includeInactive = false}) {
    return Result.guard(() async {
      final snapshot = await _firestore.collection('plans').get();
      return snapshot.docs
          .map((doc) => Plan.fromJson({...doc.data(), 'id': doc.id}))
          .where((plan) => includeInactive || plan.isActive)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    });
  }

  @override
  Stream<Subscription?> watchSubscription(String merchantId) {
    return _firestore
        .collection('subscriptions')
        .where('merchantId', isEqualTo: merchantId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final terms = snapshot.docs
          .map((doc) => Subscription.fromJson({...doc.data(), 'id': doc.id}))
          .toList()
        ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
      return terms.first;
    });
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
      if (months < 1 || amount < 0) throw const ConflictFailure();

      final now = DateTime.now();
      final existing = await watchSubscription(merchantId).first;

      // Renewing before the old term runs out adds to it. Restarting from today would
      // quietly throw away the days already paid for, which is the kind of thing a
      // merchant notices once and never forgets.
      final from = existing != null && existing.isActiveAt(now)
          ? existing.expiresAt
          : now;

      final doc = _firestore.collection('subscriptions').doc();
      final subscription = Subscription(
        id: doc.id,
        merchantId: merchantId,
        planId: planId,
        amount: amount,
        startedAt: now,
        expiresAt: from.add(const Duration(days: _daysPerMonth * 1) * months),
        recordedBy: recordedBy,
      );

      await doc.set(subscription.toJson()..remove('id'));
      // The plan moves onto the merchant as well, because that is what every feature
      // check reads. The subscription is the receipt; this is the state.
      await _firestore.collection('merchants').doc(merchantId).set(
        {'planId': planId, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      await _audit(
        action: 'recordSubscriptionPayment',
        by: recordedBy,
        details: {
          'merchantId': merchantId,
          'planId': planId,
          'amount': amount,
          'months': months,
        },
      );

      return subscription;
    });
  }

  @override
  Future<Result<void>> topUpWallet({
    required String merchantId,
    required int amount,
    required String recordedBy,
  }) {
    return Result.guard(() async {
      // Cash does not move backwards at a counter, and a negative top-up is a typo that
      // would quietly cancel somebody's credit.
      if (amount <= 0) throw const ConflictFailure();

      await _firestore.collection('merchants').doc(merchantId).set(
        {
          'walletBalance': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await _audit(
        action: 'topUpWallet',
        by: recordedBy,
        details: {'merchantId': merchantId, 'amount': amount},
      );
    });
  }

  Future<void> _audit({
    required String action,
    required String by,
    required Map<String, Object?> details,
  }) {
    return _firestore.collection('auditLog').add({
      'action': action,
      'by': by,
      ...details,
      'at': FieldValue.serverTimestamp(),
    });
  }
}

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
    final existing = await watchSubscription(merchantId).first;
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
