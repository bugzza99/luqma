/// A shop asking for a plan, before the money has been seen.
///
/// The owner's decision of 2026-09-17: a shop picks a plan and a length in MerchantApp and
/// says how it pays; the admin confirms the money arrived and activates it. The request has
/// no power of its own — only activation writes a subscription, and only an admin can.
enum SubscriptionRequestStatus { pending, activated, rejected, cancelled }

enum SubscriptionPaymentMethod { cash, transfer }

/// The lengths a shop can ask for, in months.
const subscriptionMonths = [1, 3, 6, 12];

class SubscriptionRequest {
  const SubscriptionRequest({
    required this.id,
    required this.merchantId,
    required this.planId,
    required this.months,
    required this.quotedAmount,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    this.transferReference,
    this.rejectReason,
    this.reviewedAt,
  });

  final String id;
  final String merchantId;
  final String planId;
  final int months;

  /// Piastres: the plan's monthly price times [months], computed by the server.
  final int quotedAmount;
  final SubscriptionPaymentMethod paymentMethod;
  final String? transferReference;
  final SubscriptionRequestStatus status;
  final String? rejectReason;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  bool get isPending => status == SubscriptionRequestStatus.pending;

  factory SubscriptionRequest.fromRow(Map<String, dynamic> row) => SubscriptionRequest(
        id: row['id'] as String,
        merchantId: row['merchant_id'] as String,
        planId: row['plan_id'] as String,
        months: (row['months'] as num).toInt(),
        quotedAmount: (row['quoted_amount'] as num).toInt(),
        paymentMethod: row['payment_method'] == 'transfer'
            ? SubscriptionPaymentMethod.transfer
            : SubscriptionPaymentMethod.cash,
        transferReference: row['transfer_reference'] as String?,
        status: SubscriptionRequestStatus.values.firstWhere(
          (s) => s.name == row['status'],
          orElse: () => SubscriptionRequestStatus.pending,
        ),
        rejectReason: row['reject_reason'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        reviewedAt: row['reviewed_at'] == null
            ? null
            : DateTime.parse(row['reviewed_at'] as String).toLocal(),
      );
}

/// Where a plan stands for one shop, as the admin's overview reads it.
enum PlanStanding {
  /// No plan: the shop pays by its own model (usually commission).
  none,

  /// Active, with more than [SubscriptionOverviewRow.endingSoonDays] left.
  active,

  /// Active, ending within [SubscriptionOverviewRow.endingSoonDays].
  endingSoon,

  /// The plan's end has passed and the nightly pass has not cleared it yet.
  expired,
}

class SubscriptionOverviewRow {
  const SubscriptionOverviewRow({
    required this.merchantId,
    required this.merchantName,
    this.planId,
    this.planName,
    this.planExpiresAt,
    this.revenueModel,
    this.revenueValue = 0,
    this.pendingRequestId,
  });

  static const endingSoonDays = 7;

  final String merchantId;
  final String merchantName;
  final String? planId;
  final String? planName;
  final DateTime? planExpiresAt;
  final String? revenueModel;
  final int revenueValue;
  final String? pendingRequestId;

  PlanStanding standingAt(DateTime now) {
    if (planId == null || planExpiresAt == null) return PlanStanding.none;
    if (!planExpiresAt!.isAfter(now)) return PlanStanding.expired;
    if (planExpiresAt!.difference(now) <= const Duration(days: endingSoonDays)) {
      return PlanStanding.endingSoon;
    }
    return PlanStanding.active;
  }

  factory SubscriptionOverviewRow.fromRow(Map<String, dynamic> row) =>
      SubscriptionOverviewRow(
        merchantId: row['merchant_id'] as String,
        merchantName: row['merchant_name'] as String? ?? '',
        planId: row['plan_id'] as String?,
        planName: row['plan_name'] as String?,
        planExpiresAt: row['plan_expires_at'] == null
            ? null
            : DateTime.parse(row['plan_expires_at'] as String).toLocal(),
        revenueModel: row['revenue_model'] as String?,
        revenueValue: (row['revenue_value'] as num?)?.toInt() ?? 0,
        pendingRequestId: row['pending_request_id'] as String?,
      );
}
