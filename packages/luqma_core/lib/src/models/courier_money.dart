import 'package:flutter/foundation.dart';

import 'order.dart';

/// Whose money is in the courier's hand, for one order.
///
/// A rider standing at a door with 120 ج has three questions and the app can answer all
/// three from the order in front of them: what to hand the shop, what is theirs, and what
/// the platform will want back. Every figure is integer piastres.
///
/// This is computed twice on purpose — here, and by `apply_courier_settlement` in
/// Postgres. The phone *shows* the figure and the server *decides* it, and the server's
/// answer is the one that counts; both are tested against the same numbers so a
/// disagreement fails a test rather than turning up in somebody's pocket. It is the same
/// arrangement `Revenue` and `engine.ts` had before them.
@immutable
class CourierCut {
  const CourierCut({
    required this.forShop,
    required this.forCourier,
    required this.forPlatform,
    required this.shopSettles,
  });

  /// The split for [order] at [commissionPercent], the rate from the control plane.
  factory CourierCut.of(Order order, {required double commissionPercent}) {
    final pricing = order.pricing;
    final total = pricing.total;

    // The shop's own rider hands over everything. The app has no column for what a shop
    // pays its own courier and does not invent one: saying «حسابك مع المحل» is the whole
    // truth, and a number here would be a guess presented as a fact.
    if (order.deliveryBy != DeliveryBy.platform) {
      return CourierCut(
        forShop: total,
        forCourier: 0,
        forPlatform: 0,
        shopSettles: true,
      );
    }

    // What they actually collected for the delivery. A fee discounted away is money
    // nobody received, and a percentage of it would be charging for money nobody
    // received — the same rule as «العمولة على الأكل مش على الفاتورة», from the other side.
    final fee = pricing.deliveryFee - pricing.deliveryDiscount;
    final kept = fee < 0 ? 0 : fee;

    // `~/` and a bps integer, because that is what Postgres does: `(basis * bps) / 10000`
    // on integers truncates. Rounding here would put the phone a piastre above the
    // server on half the orders in the city.
    final bps = (commissionPercent * 100).round();
    final commission = (kept * bps) ~/ 10000;

    return CourierCut(
      // What is left of the cash once their own share comes out — the food money, and
      // whatever the shop is owed on it. Derived from the total rather than re-added from
      // the parts, so a coupon that lowered the bill lowers this too.
      forShop: total - kept,
      forCourier: kept - commission,
      forPlatform: commission,
      shopSettles: false,
    );
  }

  /// Cash to hand the shop.
  final int forShop;

  /// What the courier keeps once the platform's share is out.
  final int forCourier;

  /// The platform's share of the delivery. Not cash now — it accrues and is collected
  /// weekly, the same way a shop's commission is.
  final int forPlatform;

  /// True when the shop delivered with its own rider, so the whole bill goes back to the
  /// shop and the rider's own pay is a matter between them.
  final bool shopSettles;

  @override
  bool operator ==(Object other) =>
      other is CourierCut &&
      other.forShop == forShop &&
      other.forCourier == forCourier &&
      other.forPlatform == forPlatform &&
      other.shopSettles == shopSettles;

  @override
  int get hashCode => Object.hash(forShop, forCourier, forPlatform, shopSettles);
}

/// What a courier did over one stretch of time.
@immutable
class CourierSpan {
  const CourierSpan({
    this.delivered = 0,
    this.returned = 0,
    this.cash = 0,
    this.fees = 0,
    this.commission = 0,
    this.net = 0,
  });

  factory CourierSpan.fromJson(Map<String, dynamic> json) => CourierSpan(
        delivered: (json['delivered'] as num?)?.toInt() ?? 0,
        returned: (json['returned'] as num?)?.toInt() ?? 0,
        cash: (json['cash'] as num?)?.toInt() ?? 0,
        fees: (json['fees'] as num?)?.toInt() ?? 0,
        commission: (json['commission'] as num?)?.toInt() ?? 0,
        net: (json['net'] as num?)?.toInt() ?? 0,
      );

  static const empty = CourierSpan();

  /// Orders that reached the door.
  final int delivered;

  /// Trips made where the customer refused or was not there. Counted apart from an order
  /// the customer cancelled before it ever left, and carrying no money.
  final int returned;

  /// Everything collected from customers, in piastres — most of it the shops'.
  final int cash;

  /// The delivery fees on those orders: the part that was the courier's to keep.
  final int fees;

  /// What the platform is owed out of those fees.
  final int commission;

  /// [fees] less [commission] — computed by the server, so the figure a courier argues
  /// from and the figure the owner collects against come from one statement.
  final int net;

  bool get isEmpty => delivered == 0 && returned == 0;
}

/// Today, this week and this month, from one call.
@immutable
class CourierEarnings {
  const CourierEarnings({
    this.today = CourierSpan.empty,
    this.week = CourierSpan.empty,
    this.month = CourierSpan.empty,
  });

  factory CourierEarnings.fromJson(Map<String, dynamic> json) {
    CourierSpan span(String key) => switch (json[key]) {
          final Map<String, dynamic> map => CourierSpan.fromJson(map),
          final Map map => CourierSpan.fromJson(Map<String, dynamic>.from(map)),
          _ => CourierSpan.empty,
        };
    return CourierEarnings(
      today: span('today'),
      week: span('week'),
      month: span('month'),
    );
  }

  static const empty = CourierEarnings();

  final CourierSpan today;

  /// From Saturday, because that is the week somebody settles up for — not a rolling
  /// seven days that never lines up with the conversation they are about to have.
  final CourierSpan week;

  /// The calendar month.
  final CourierSpan month;
}
