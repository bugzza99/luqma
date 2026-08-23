// freezed forwards `@RequiredTimestampConverter` from a constructor parameter onto the
// generated field, which the analyzer reports as an invalid target. Scoped to this file.
// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import 'converters.dart';

part 'billing.freezed.dart';
part 'billing.g.dart';

/// What a plan actually gets a merchant.
///
/// Every one of these is read somewhere and nothing is decorative. They live in the
/// `plans` collection and are edited from AdminApp — a price or a limit hard-coded in the
/// app is a price that needs a Play Store release to change.
@freezed
abstract class PlanFeatures with _$PlanFeatures {
  const factory PlanFeatures({
    /// Zero means unlimited, not "none allowed".
    ///
    /// It reads backwards, which is why [hasUnlimitedItems] exists: a plan that silently
    /// allowed no items at all would look like a bug in the menu editor rather than a
    /// pricing decision, and somebody would spend an afternoon on it.
    @Default(0) int maxItems,
    @Default(false) bool verifiedBadge,
    @Default(false) bool analytics,
    @Default(false) bool boostRank,
    @Default(0) int homeBannerSlots,
    @Default(0) int monthlyPromotionCount,
  }) = _PlanFeatures;

  const PlanFeatures._();

  factory PlanFeatures.fromJson(Map<String, dynamic> json) =>
      _$PlanFeaturesFromJson(json);

  bool get hasUnlimitedItems => maxItems <= 0;

  /// Whether a menu of [count] items is within this plan.
  bool allowsItems(int count) => hasUnlimitedItems || count <= maxItems;
}

@freezed
abstract class Plan with _$Plan {
  const factory Plan({
    required String id,
    required String name,

    /// Piastres per month. Zero is the Free plan, which is permanent: a marketplace
    /// empty of merchants is dead, so unpaid merchants still work in our favour.
    @Default(0) int priceMonthly,
    @Default(PlanFeatures()) PlanFeatures features,
    @Default(0) int sortOrder,

    /// A withdrawn plan stops being offered but stays readable, so merchants already on
    /// it keep what they paid for.
    @Default(true) bool isActive,
  }) = _Plan;

  const Plan._();

  factory Plan.fromJson(Map<String, dynamic> json) => _$PlanFromJson(json);

  bool get isFree => priceMonthly <= 0;
}

/// One paid term.
///
/// A record of cash that changed hands in a shop, which is why it names who recorded it.
/// Expiry is a date passing rather than a flag somebody has to remember to flip.
@freezed
abstract class Subscription with _$Subscription {
  const factory Subscription({
    required String id,
    required String merchantId,
    required String planId,

    /// Piastres actually collected.
    required int amount,
    @RequiredTimestampConverter() required DateTime startedAt,
    @RequiredTimestampConverter() required DateTime expiresAt,

    /// The admin who took the money. Without a name on it, a disputed payment has
    /// nobody to ask.
    required String recordedBy,
  }) = _Subscription;

  const Subscription._();

  factory Subscription.fromJson(Map<String, dynamic> json) =>
      _$SubscriptionFromJson(json);

  bool isActiveAt(DateTime now) => now.isBefore(expiresAt);

  int daysLeftAt(DateTime now) {
    final left = expiresAt.difference(now).inDays;
    return left < 0 ? 0 : left;
  }
}
