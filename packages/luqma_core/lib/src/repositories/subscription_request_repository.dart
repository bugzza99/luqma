import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/billing.dart';
import '../models/subscription_request.dart';
import '../result.dart';

/// Asking for a plan (a shop) and answering (an admin).
///
/// Every write is a server function: the table has no client write policy, so a shop cannot
/// mark its own request activated and nothing here computes a price the server would trust.
abstract interface class SubscriptionRequestRepository {
  /// A shop's requests, newest first.
  Future<Result<List<SubscriptionRequest>>> forMerchant(String merchantId);

  /// Every pending request in the city, oldest first — the order they should be answered in.
  Future<Result<List<SubscriptionRequest>>> pending();

  Future<Result<SubscriptionRequest>> request({
    required String planId,
    required int months,
    required SubscriptionPaymentMethod paymentMethod,
    String? transferReference,
  });

  Future<Result<void>> cancel(String requestId);

  /// Activates after the money has been seen. [amount] overrides the quote — a discount.
  Future<Result<void>> activate(String requestId, {int? amount});

  Future<Result<void>> reject(String requestId, String reason);

  /// Every shop and where its plan stands.
  Future<Result<List<SubscriptionOverviewRow>>> overview();
}

class SupabaseSubscriptionRequestRepository implements SubscriptionRequestRepository {
  SupabaseSubscriptionRequestRepository(this._db);

  final SupabaseClient _db;

  static List<SubscriptionRequest> _rows(Object? data) => [
        for (final row in (data as List? ?? const []))
          SubscriptionRequest.fromRow(Map<String, dynamic>.from(row as Map)),
      ];

  @override
  Future<Result<List<SubscriptionRequest>>> forMerchant(String merchantId) {
    return Result.guard(() async => _rows(await _db
        .from('subscription_requests')
        .select()
        .eq('merchant_id', merchantId)
        .order('created_at', ascending: false)));
  }

  @override
  Future<Result<List<SubscriptionRequest>>> pending() {
    return Result.guard(() async => _rows(await _db
        .from('subscription_requests')
        .select()
        .eq('status', 'pending')
        .order('created_at', ascending: true)));
  }

  @override
  Future<Result<SubscriptionRequest>> request({
    required String planId,
    required int months,
    required SubscriptionPaymentMethod paymentMethod,
    String? transferReference,
  }) {
    return Result.guard(() async {
      final row = await _db.rpc('request_subscription', params: {
        'p_plan_id': planId,
        'p_months': months,
        'p_payment_method': paymentMethod.name,
        'p_reference': transferReference,
      });
      return SubscriptionRequest.fromRow(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<Result<void>> cancel(String requestId) => Result.guard(
        () => _db.rpc('cancel_subscription_request', params: {'p_id': requestId}),
      );

  @override
  Future<Result<void>> activate(String requestId, {int? amount}) => Result.guard(
        () => _db.rpc('activate_subscription_request', params: {
          'p_id': requestId,
          'p_amount': amount,
        }),
      );

  @override
  Future<Result<void>> reject(String requestId, String reason) => Result.guard(
        () => _db.rpc('reject_subscription_request', params: {
          'p_id': requestId,
          'p_reason': reason,
        }),
      );

  @override
  Future<Result<List<SubscriptionOverviewRow>>> overview() {
    return Result.guard(() async {
      final rows = await _db.rpc('admin_subscriptions');
      return [
        for (final row in (rows as List? ?? const []))
          SubscriptionOverviewRow.fromRow(Map<String, dynamic>.from(row as Map)),
      ];
    });
  }
}

/// In-memory requests that apply the server's rules: one pending request per shop, a price
/// computed from the plan, only pending requests can be answered, a reason to reject.
class FakeSubscriptionRequestRepository implements SubscriptionRequestRepository {
  FakeSubscriptionRequestRepository({
    this.plans = const [],
    this.merchantId,
    this.overviewRows = const [],
    List<SubscriptionRequest> seed = const [],
    this.failure,
    DateTime Function()? clock,
  })  : _requests = [...seed],
        _clock = clock ?? DateTime.now;

  final List<Plan> plans;

  /// The shop the signed-in owner runs; null for an admin.
  final String? merchantId;
  final List<SubscriptionOverviewRow> overviewRows;
  final Failure? failure;
  final DateTime Function() _clock;
  final List<SubscriptionRequest> _requests;

  /// What [activate] was asked, for assertions.
  final List<(String, int?)> activations = [];

  List<SubscriptionRequest> get all => List.unmodifiable(_requests);

  SubscriptionRequest _with(SubscriptionRequest r, SubscriptionRequestStatus status,
          {String? reason}) =>
      SubscriptionRequest(
        id: r.id,
        merchantId: r.merchantId,
        planId: r.planId,
        months: r.months,
        quotedAmount: r.quotedAmount,
        paymentMethod: r.paymentMethod,
        transferReference: r.transferReference,
        status: status,
        rejectReason: reason ?? r.rejectReason,
        createdAt: r.createdAt,
        reviewedAt: status == SubscriptionRequestStatus.cancelled ? r.reviewedAt : _clock(),
      );

  Result<void> _answer(String id, SubscriptionRequestStatus to, {String? reason}) {
    final i = _requests.indexWhere((r) => r.id == id);
    if (i < 0) return const Result.err(NotFoundFailure());
    if (!_requests[i].isPending) return const Result.err(ConflictFailure());
    _requests[i] = _with(_requests[i], to, reason: reason);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<SubscriptionRequest>>> forMerchant(String merchantId) async {
    if (failure != null) return Result.err(failure!);
    // An owner reads their own shop's rows only, as the policy allows.
    if (this.merchantId != null && this.merchantId != merchantId) return const Result.ok([]);
    final mine = _requests.where((r) => r.merchantId == merchantId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Result.ok(mine);
  }

  @override
  Future<Result<List<SubscriptionRequest>>> pending() async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_requests
        .where((r) => r.isPending && (merchantId == null || r.merchantId == merchantId))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }

  @override
  Future<Result<SubscriptionRequest>> request({
    required String planId,
    required int months,
    required SubscriptionPaymentMethod paymentMethod,
    String? transferReference,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (merchantId == null) return const Result.err(PermissionFailure());
    final plan = plans.where((p) => p.id == planId && p.isActive).firstOrNull;
    if (plan == null || !subscriptionMonths.contains(months)) {
      return const Result.err(ValidationFailure());
    }
    if (_requests.any((r) => r.merchantId == merchantId && r.isPending)) {
      return const Result.err(ConflictFailure());
    }
    final reference = transferReference?.trim();
    if (reference != null && reference.length > 80) return const Result.err(ValidationFailure());
    final created = SubscriptionRequest(
      id: 'req-${_requests.length + 1}',
      merchantId: merchantId!,
      planId: planId,
      months: months,
      quotedAmount: plan.priceMonthly * months,
      paymentMethod: paymentMethod,
      transferReference: reference == null || reference.isEmpty ? null : reference,
      status: SubscriptionRequestStatus.pending,
      createdAt: _clock(),
    );
    _requests.add(created);
    return Result.ok(created);
  }

  @override
  Future<Result<void>> cancel(String requestId) async {
    if (failure != null) return Result.err(failure!);
    final r = _requests.where((r) => r.id == requestId).firstOrNull;
    if (r != null && r.merchantId != merchantId) return const Result.err(PermissionFailure());
    return _answer(requestId, SubscriptionRequestStatus.cancelled);
  }

  @override
  Future<Result<void>> activate(String requestId, {int? amount}) async {
    if (failure != null) return Result.err(failure!);
    if (merchantId != null) return const Result.err(PermissionFailure());
    if (amount != null && amount < 0) return const Result.err(ValidationFailure());
    final result = _answer(requestId, SubscriptionRequestStatus.activated);
    if (result is Ok) activations.add((requestId, amount));
    return result;
  }

  @override
  Future<Result<void>> reject(String requestId, String reason) async {
    if (failure != null) return Result.err(failure!);
    if (merchantId != null) return const Result.err(PermissionFailure());
    if (reason.trim().isEmpty) return const Result.err(ValidationFailure());
    return _answer(requestId, SubscriptionRequestStatus.rejected, reason: reason.trim());
  }

  @override
  Future<Result<List<SubscriptionOverviewRow>>> overview() async {
    if (failure != null) return Result.err(failure!);
    if (merchantId != null) return const Result.err(PermissionFailure());
    return Result.ok(overviewRows);
  }
}
