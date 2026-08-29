import 'package:freezed_annotation/freezed_annotation.dart';

import 'converters.dart';
import 'merchant.dart';

part 'settlement.freezed.dart';
part 'settlement.g.dart';

/// What the platform took from one delivered order.
///
/// One row per order, written by the database at the moment the courier marks it
/// delivered — cash reaches the merchant at the door, so that is the only moment the
/// platform's share is real.
///
/// This is the *evidence*, not the answer. `Merchant.commissionOwed` and
/// `Merchant.walletBalance` are the running totals a screen shows and `place_order`
/// checks; these rows are what somebody reads out when a merchant disputes one of them,
/// which is a conversation that happens in a shop with a phone on the counter.
@freezed
abstract class OrderSettlement with _$OrderSettlement {
  const factory OrderSettlement({
    required String orderId,
    required String merchantId,

    /// The terms as they stood when the order was placed, copied — never read back off
    /// the merchant, who may be on a different model by now.
    required RevenueModel model,

    /// What the cut was charged on: the food, never the bill.
    required int basis,

    /// What the platform took, in piastres.
    required int amount,

    /// What the platform owes *back*, from a platform-funded coupon. With cash a
    /// discount is simply less money reaching the merchant, so this is a debt from the
    /// moment the order was placed.
    @Default(0) int platformOwes,

    @TimestampConverter() DateTime? settledAt,

    /// Set when the charge was taken back — an admin moved the order out of delivered.
    ///
    /// The row stays rather than disappearing: "charged and then returned" and "never
    /// charged" are different answers, and only one of them is something a merchant
    /// should have to be told about.
    @TimestampConverter() DateTime? reversedAt,
  }) = _OrderSettlement;

  const OrderSettlement._();

  factory OrderSettlement.fromJson(Map<String, dynamic> json) =>
      _$OrderSettlementFromJson(json);

  /// Whether this charge still stands.
  bool get isCharged => reversedAt == null;
}

/// A merchant's account at a glance.
///
/// Summed in Dart from the rows rather than asked of the database, deliberately: the
/// statement screen needs the rows anyway, so an aggregate would be a second round trip
/// to answer a question the first one already contains. That stops being true when a
/// merchant has a year behind them — at which point the right move is a SQL function,
/// not a bigger fetch.
@freezed
abstract class SettlementSummary with _$SettlementSummary {
  const factory SettlementSummary({
    /// Orders that were charged and not taken back.
    @Default(0) int orders,

    /// What the platform took across them.
    @Default(0) int taken,

    /// What the platform owes the merchant, from platform-funded discounts.
    @Default(0) int platformOwes,
  }) = _SettlementSummary;

  const SettlementSummary._();

  /// Reversed rows count for nothing in either direction.
  factory SettlementSummary.of(Iterable<OrderSettlement> settlements) {
    var orders = 0;
    var taken = 0;
    var owes = 0;
    for (final s in settlements.where((s) => s.isCharged)) {
      orders++;
      taken += s.amount;
      owes += s.platformOwes;
    }
    return SettlementSummary(orders: orders, taken: taken, platformOwes: owes);
  }
}
