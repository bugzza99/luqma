import 'package:freezed_annotation/freezed_annotation.dart';

import 'converters.dart';
import 'revenue.dart';

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

    /// The approved picture's address, resolved by the query that read this merchant.
    ///
    /// Null covers three different things and deliberately collapses them: no picture
    /// was ever uploaded, one was uploaded and is still waiting for an admin, or one was
    /// refused. All three mean the same thing to a customer — there is no photograph —
    /// and `LuqmaImage` draws the tinted mark from the shop's name instead.
    ///
    /// Not written back: `_row` never carries these, exactly as it never carries
    /// `walletBalance`. The id is the merchant's to set; the URL and whether it may be
    /// shown are the media table's answer.
    String? logoUrl,
    String? coverUrl,

    /// Zones this merchant will deliver to. Empty means its own zone only.
    @Default(<String>[]) List<String> servedZones,

    /// False when Luqma's own courier delivers for them.
    @Default(true) bool deliversSelf,
    String? ownerUid,
    @Default(<MenuCategory>[]) List<MenuCategory> menuCategories,
    String? planId,
    @Default(RevenueModel.subscription) RevenueModel revenueModel,

    /// The rate or fee in force: **basis points** under commission, **piastres per
    /// order** under prepaid, and meaningless under a subscription.
    ///
    /// Not the prepaid balance, which the data-model note once said — that is
    /// [walletBalance]. Two fields meaning the same thing is how they come to disagree.
    @Default(0) int revenueValue,

    /// Remaining prepaid credit, in piastres. Only ever moved by the server.
    @Default(0) int walletBalance,

    /// What this merchant owes the platform under `commission`, in piastres.
    ///
    /// A running total the settlement maintains on delivery, and absent from `_row` for
    /// the same reason [walletBalance] is: it is the server's money, and a form built
    /// from this model must not be able to carry a new figure back.
    ///
    /// The evidence behind it is `order_settlements`, one row per delivered order. This
    /// is the answer; that is the working.
    @Default(0) int commissionOwed,

    /// Overrides the zone's default delivery fee, in piastres. Clamped server-side to
    /// the admin's range — the client is not trusted with it.
    int? deliveryFeeOverride,
    @Default(0) int minOrder,
    @Default(0) double ratingAvg,
    @Default(0) int ratingCount,

    /// Roughly how long the kitchen takes, in minutes.
    ///
    /// One number rather than a range: Edku is ten minutes across on a motorbike, so
    /// what actually differs between two shops is the kitchen, not the distance — and a
    /// "25–35" built from two hand-typed numbers reads as a precision nobody measured.
    /// The database bounds it between 5 and 180, because 600 is a typo.
    @Default(30) int prepMinutes,
  }) = _Merchant;

  const Merchant._();

  factory Merchant.fromJson(Map<String, dynamic> json) => _$MerchantFromJson(json);

  /// The single question the whole app asks about a merchant, derived rather than
  /// stored so its three inputs can never disagree.
  bool acceptsOrdersAt(DateTime now) {
    if (status != MerchantStatus.approved) return false;
    if (pausedUntil != null && now.isBefore(pausedUntil!)) return false;
    // A prepaid merchant whose wallet has run out stops appearing as open, exactly like
    // one outside its hours. Letting orders through would mean the platform carries
    // them for nothing and then argues about it afterwards.
    if (!Revenue.canAffordAnOrder(this)) return false;
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
