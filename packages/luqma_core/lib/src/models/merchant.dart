import 'package:freezed_annotation/freezed_annotation.dart';

import 'converters.dart';

part 'merchant.freezed.dart';
part 'merchant.g.dart';

enum MerchantType {
  /// Takes instant orders and delivers with its own courier.
  restaurant,

  /// Publishes a limited number of portions in advance, with a pickup window.
  homeKitchen,
}

enum MerchantStatus { pending, approved, suspended }

/// How the platform earns from this merchant. Set per merchant from AdminApp and frozen
/// onto each order as it is placed, so changing it never rewrites past accounting.
enum RevenueModel { subscription, commission, prepaid }

/// One stretch of a single weekday during which orders are accepted.
///
/// Times are minutes from midnight rather than a clock type: they serialise as plain
/// integers, sort without parsing, and survive a timezone change on the device.
/// [closeMinute] at or below [openMinute] means the window runs past midnight, which is
/// the normal case for a restaurant here rather than an edge case.
@freezed
abstract class OpeningWindow with _$OpeningWindow {
  const factory OpeningWindow({
    /// `DateTime.monday` … `DateTime.sunday`.
    required int weekday,
    required int openMinute,
    required int closeMinute,
  }) = _OpeningWindow;

  const OpeningWindow._();

  factory OpeningWindow.fromJson(Map<String, dynamic> json) =>
      _$OpeningWindowFromJson(json);

  bool get crossesMidnight => closeMinute <= openMinute;

  /// Whether [time] falls inside this window, given the window belongs to [weekday].
  bool contains(DateTime time) {
    final minute = time.hour * 60 + time.minute;

    if (!crossesMidnight) {
      return time.weekday == weekday && minute >= openMinute && minute < closeMinute;
    }

    // An overnight window covers two calendar days: the evening of its own weekday, and
    // the small hours of the day after. Checking only the clock would also reopen the
    // merchant on the *morning* of its own weekday, hours before it ever opened.
    final previousWeekday = time.weekday == DateTime.monday
        ? DateTime.sunday
        : time.weekday - 1;

    if (time.weekday == weekday && minute >= openMinute) return true;
    if (previousWeekday == weekday && minute < closeMinute) return true;
    return false;
  }
}

@freezed
abstract class Merchant with _$Merchant {
  const factory Merchant({
    required String id,
    required String cityId,
    required MerchantType type,
    required String name,

    /// The zone the merchant sits in.
    required String zoneId,
    required String phone,
    @Default(MerchantStatus.pending) MerchantStatus status,
    @Default(<OpeningWindow>[]) List<OpeningWindow> openingHours,

    /// Set from MerchantApp when a rush hits. A timestamp rather than a flag, so it
    /// lapses on its own instead of leaving a merchant invisible until someone
    /// remembers to undo it.
    @TimestampConverter() DateTime? pausedUntil,
    String? logoMediaId,
    String? coverMediaId,

    /// Zones this merchant will deliver to. Empty means its own zone only.
    @Default(<String>[]) List<String> servedZones,

    /// False when Luqma's own courier delivers for them.
    @Default(true) bool deliversSelf,
    String? ownerUid,
    @Default(<MenuCategory>[]) List<MenuCategory> menuCategories,
    String? planId,
    @Default(RevenueModel.subscription) RevenueModel revenueModel,

    /// Commission rate in basis points, or the prepaid balance in piastres, depending
    /// on [revenueModel]. Meaningless under a subscription.
    @Default(0) int revenueValue,
    @Default(0) int walletBalance,

    /// Overrides the zone's default delivery fee, in piastres. Clamped server-side to
    /// the admin's range — the client is not trusted with it.
    int? deliveryFeeOverride,
    @Default(0) int minOrder,
    @Default(0) double ratingAvg,
    @Default(0) int ratingCount,
  }) = _Merchant;

  const Merchant._();

  factory Merchant.fromJson(Map<String, dynamic> json) => _$MerchantFromJson(json);

  /// The single question the whole app asks about a merchant, derived rather than
  /// stored so its three inputs can never disagree.
  bool acceptsOrdersAt(DateTime now) {
    if (status != MerchantStatus.approved) return false;
    if (pausedUntil != null && now.isBefore(pausedUntil!)) return false;
    return openingHours.any((window) => window.contains(now));
  }
}

/// A menu section. Inline on the merchant rather than its own collection: a menu has
/// five to ten of these, and a separate collection bought one extra read per screen.
@freezed
abstract class MenuCategory with _$MenuCategory {
  const factory MenuCategory({
    required String id,
    required String name,
    @Default(0) int sortOrder,
  }) = _MenuCategory;

  factory MenuCategory.fromJson(Map<String, dynamic> json) =>
      _$MenuCategoryFromJson(json);
}
