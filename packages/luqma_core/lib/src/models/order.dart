import 'package:freezed_annotation/freezed_annotation.dart';

import 'converters.dart';
import 'coupon.dart';
import 'geography.dart';
import 'merchant.dart';

part 'order.freezed.dart';
part 'order.g.dart';

enum OrderType {
  /// Placed now, cooked now.
  instant,

  /// A reserved portion of a home kitchen's published meal, collected in its window.
  preorder,
}

enum OrderStatus {
  placed,
  accepted,
  preparing,
  outForDelivery,
  delivered,
  cancelled,

  /// The merchant let the accept deadline pass. Raised for the admin, never shown to
  /// the customer as an error — someone is about to phone the restaurant.
  needsAttention,
}

/// Whose courier takes this order out.
///
/// Frozen onto the order rather than read from the merchant, like everything else here
/// that decides responsibility: a merchant who stops delivering their own orders next
/// week must not change who was answerable for last week's.
enum DeliveryBy {
  /// The merchant's own courier.
  merchant,

  /// Luqma's courier. Home kitchens, and merchants with `deliversSelf = false`.
  platform,
}

/// Who is asking to move an order. Every transition is checked against this, because
/// most of the rules are about *who*, not about *what*.
enum OrderActor { customer, merchant, courier, admin, system }

extension OrderTransitions on OrderStatus {
  /// The transitions each party is allowed to make.
  ///
  /// Enforced again in the security rules; this copy exists so the interface can hide a
  /// button rather than offer an action that will be refused.
  bool canMoveTo(OrderStatus next, {required OrderActor by}) {
    if (this == next) return false;
    // Delivered and cancelled are final for everyone but the admin. The server stays
    // authoritative for admin — it already allows reopening a finished order — so the
    // interface must not hide a button the server would honour. Two sources of truth
    // would disagree only as an owner staring at a stuck order.
    if (this == OrderStatus.delivered || this == OrderStatus.cancelled) {
      return by == OrderActor.admin;
    }

    return switch (by) {
      OrderActor.customer =>
        this == OrderStatus.placed && next == OrderStatus.cancelled,
      OrderActor.merchant => switch (this) {
          OrderStatus.placed =>
            next == OrderStatus.accepted || next == OrderStatus.cancelled,
          OrderStatus.accepted =>
            next == OrderStatus.preparing || next == OrderStatus.cancelled,
          OrderStatus.preparing => next == OrderStatus.outForDelivery,
          _ => false,
        },
      OrderActor.courier => switch (this) {
          OrderStatus.preparing => next == OrderStatus.outForDelivery,
          OrderStatus.outForDelivery =>
            next == OrderStatus.delivered || next == OrderStatus.cancelled,
          _ => false,
        },
      // Only ever raises the flag, and only on an order nobody has answered.
      OrderActor.system =>
        this == OrderStatus.placed && next == OrderStatus.needsAttention,
      OrderActor.admin => true,
    };
  }
}

/// One line of a basket.
@freezed
abstract class OrderLine with _$OrderLine {
  const factory OrderLine({
    required String itemId,

    /// Copied at order time. A menu that changes tomorrow must not rewrite what someone
    /// ordered today.
    required String name,

    /// Piastres.
    required int unitPrice,
    required int quantity,

    /// Piastres of chosen extras, per unit.
    ///
    /// Written by the server from [optionIds] and the menu. What the phone sends here is
    /// ignored: a number nobody can verify is a number nobody should read.
    @Default(0) int optionsTotal,

    /// Which extras were chosen, by id.
    ///
    /// The ids rather than a total, because the total is the one figure on an order that
    /// the server could not check — it had no idea what had been selected. A crafted
    /// request could ask for every extra on the menu and claim they were free, and the
    /// merchant would hand over the food and collect the base price in cash.
    @Default(<String>[]) List<String> optionIds,
    String? note,
  }) = _OrderLine;

  const OrderLine._();

  factory OrderLine.fromJson(Map<String, dynamic> json) => _$OrderLineFromJson(json);

  int get lineTotal => (unitPrice + optionsTotal) * quantity;
}

/// What the courier collects, and who owes what.
///
/// A pure computation so the phone and the Cloud Function produce the same number from
/// the same basket. With cash, the figure the app shows is the figure a person hands
/// over, so the server recomputes this and refuses an order whose total disagrees.
@freezed
abstract class OrderPricing with _$OrderPricing {
  const factory OrderPricing({
    required int subtotal,
    required int deliveryFee,
    @Default(0) int subtotalDiscount,
    @Default(0) int deliveryDiscount,
    required int total,

    /// Carried on the order itself so a platform-funded campaign accrues as a debt from
    /// the first order rather than being reconstructed from memory at month end.
    @Default(0) int platformOwesMerchant,
  }) = _OrderPricing;

  const OrderPricing._();

  factory OrderPricing.fromJson(Map<String, dynamic> json) =>
      _$OrderPricingFromJson(json);

  static OrderPricing compute({
    required List<OrderLine> items,
    required int deliveryFee,
    CouponAccepted? coupon,
  }) {
    final subtotal = items.fold(0, (sum, line) => sum + line.lineTotal);

    // An empty basket is not an order, so it must not still owe a delivery fee.
    if (subtotal == 0) {
      return const OrderPricing(subtotal: 0, deliveryFee: 0, total: 0);
    }

    final subtotalDiscount = coupon?.subtotalDiscount ?? 0;
    final deliveryDiscount = coupon?.deliveryDiscount ?? 0;
    final total = subtotal - subtotalDiscount + deliveryFee - deliveryDiscount;

    return OrderPricing(
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      subtotalDiscount: subtotalDiscount,
      deliveryDiscount: deliveryDiscount,
      // A courier cannot hand money back at the door.
      total: total < 0 ? 0 : total,
      platformOwesMerchant: coupon?.platformOwesMerchant ?? 0,
    );
  }
}

/// The revenue terms in force when the order was placed.
///
/// Frozen onto the order so that changing a merchant's model in AdminApp affects future
/// orders only, and never rewrites what was already agreed.
@freezed
abstract class RevenueSnapshot with _$RevenueSnapshot {
  const factory RevenueSnapshot({
    required RevenueModel model,

    /// The rate or fee in force: basis points under commission, piastres per order
    /// under prepaid, and meaningless under a subscription.
    @Default(0) int value,

    /// What was actually taken, once the order was delivered. Zero until then.
    @Default(0) int amount,
  }) = _RevenueSnapshot;

  const RevenueSnapshot._();

  factory RevenueSnapshot.fromJson(Map<String, dynamic> json) =>
      _$RevenueSnapshotFromJson(json);

  /// The terms in force for [merchant] right now.
  ///
  /// Taken once, at order creation, and never read from the merchant again. That is what
  /// makes the model switchable at runtime without rewriting history.
  factory RevenueSnapshot.of(Merchant merchant) => RevenueSnapshot(
        model: merchant.revenueModel,
        value: merchant.revenueValue,
      );
}

@freezed
abstract class Order with _$Order {
  const factory Order({
    required String id,
    required String cityId,
    required int orderNumber,
    required String customerUid,
    required String customerName,
    required String customerPhone,
    required String merchantId,
    required String merchantName,
    required String zoneId,

    /// The address as it stood when the order was placed.
    ///
    /// A copy, not a reference. A courier cannot read another person's address
    /// collection — the rules see to that — so a reference would render as nothing at
    /// the one moment it is needed. And an address corrected next month must not
    /// rewrite where last week's order actually went.
    ///
    /// Nullable only so that an order written before this field existed still opens
    /// rather than crashing the screen a courier is standing in the street holding.
    Address? address,
    @Default(DeliveryBy.merchant) DeliveryBy deliveryBy,
    required OrderType type,
    required List<OrderLine> items,
    required OrderPricing pricing,
    @Default(OrderStatus.placed) OrderStatus status,

    /// Set on a customer with no delivered order yet, so the merchant can confirm by
    /// phone before cooking.
    @Default(false) bool isNewCustomer,
    String? couponCode,
    String? courierUid,
    String? cancelReason,
    OrderActor? cancelledBy,
    RevenueSnapshot? revenue,
    @TimestampConverter() DateTime? placedAt,
    @TimestampConverter() DateTime? acceptDeadlineAt,
    @TimestampConverter() DateTime? deliveredAt,

    /// Minutes the merchant quoted when accepting.
    int? prepMinutes,
  }) = _Order;

  const Order._();

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);

  /// When the merchant must have answered by.
  ///
  /// A pre-order has no deadline: publishing the meal was the acceptance. Giving it one
  /// would flag every pre-order to the admin minutes after it was placed.
  static DateTime? deadlineFor({
    required OrderType type,
    required DateTime placedAt,
    required int timeoutMinutes,
  }) {
    if (type == OrderType.preorder) return null;
    return placedAt.add(Duration(minutes: timeoutMinutes));
  }

  bool get isOpen =>
      status != OrderStatus.delivered && status != OrderStatus.cancelled;
}
