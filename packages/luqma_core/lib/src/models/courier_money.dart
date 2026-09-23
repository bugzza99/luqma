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
  ///
  /// [onPlatformRoster] is whether this rider carries for the platform itself — an
  /// active `courier_merchants` row with no shop. It is the question
  /// `apply_courier_settlement` asks before it charges anything (`notPlatformCourier`),
  /// and it is required rather than defaulted because a caller who forgets it would show
  /// a shop's rider a commission the server never records.
  factory CourierCut.of(
    Order order, {
    required bool onPlatformRoster,
    required double commissionPercent,
  }) {
    final pricing = order.pricing;
    final total = pricing.total;

    // The shop's own rider hands over everything. The app has no column for what a shop
    // pays its own courier and does not invent one: saying «حسابك مع المحل» is the whole
    // truth, and a number here would be a guess presented as a fact. A shop's rider who
    // picked up a platform order is the same case to the server, so it is here too.
    if (order.deliveryBy != DeliveryBy.platform || !onPlatformRoster) {
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

/// Why a delivery was charged what it was charged.
///
/// Stored on every settled order including the zeros, so «اتحسب عليك صفر» is a fact with
/// a reason behind it rather than a row that is simply not there.
enum CourierGround {
  /// A platform delivery by a platform courier: the fee was theirs, so a share of it is
  /// the platform's.
  platform,

  /// The shop delivered with its own rider. The fee was never the courier's.
  merchantDelivery,

  /// Carried for a shop rather than for the platform, on an order the platform owned.
  notPlatformCourier;

  static CourierGround parse(String? raw) => switch (raw) {
        'platform' => CourierGround.platform,
        'notPlatformCourier' => CourierGround.notPlatformCourier,
        _ => CourierGround.merchantDelivery,
      };
}

/// One line of a courier's statement: a delivery, and what it cost them.
@immutable
class CourierCharge {
  const CourierCharge({
    required this.orderId,
    required this.basis,
    required this.bps,
    required this.amount,
    required this.ground,
    required this.settledAt,
    this.reversedAt,
    this.orderNumber,
    this.merchantName,
  });

  factory CourierCharge.fromRow(Map<String, dynamic> row) {
    // The order is embedded, and an embed the policy cannot satisfy comes back null
    // rather than refused. A line with no order still belongs on the statement — the
    // money moved — so the name and number are optional and the screen says so.
    final order = switch (row['orders']) {
      final Map order => order,
      _ => null,
    };
    return CourierCharge(
      orderId: row['order_id'] as String,
      basis: (row['basis'] as num?)?.toInt() ?? 0,
      bps: (row['bps'] as num?)?.toInt() ?? 0,
      amount: (row['amount'] as num?)?.toInt() ?? 0,
      ground: CourierGround.parse(row['ground'] as String?),
      settledAt: DateTime.parse(row['settled_at'] as String).toLocal(),
      reversedAt: switch (row['reversed_at']) {
        final String at => DateTime.parse(at).toLocal(),
        _ => null,
      },
      orderNumber: (order?['order_number'] as num?)?.toInt(),
      merchantName: order?['merchant_name'] as String?,
    );
  }

  final String orderId;

  /// The delivery fee this courier kept, which the charge is a percentage of.
  final int basis;

  /// The rate applied, frozen at the moment of delivery. Kept so an old line still
  /// explains itself after the rate has moved.
  final int bps;

  final int amount;
  final CourierGround ground;
  final DateTime settledAt;

  /// Set when the delivery stopped being a delivery and the charge was handed back.
  final DateTime? reversedAt;

  final int? orderNumber;
  final String? merchantName;

  bool get isReversed => reversedAt != null;

  /// The rate as a percentage, for showing beside the amount.
  double get percent => bps / 100;
}

/// Cash a courier handed over, and when.
@immutable
class CourierPayment {
  const CourierPayment({
    required this.id,
    required this.amount,
    required this.createdAt,
    this.note,
  });

  factory CourierPayment.fromRow(Map<String, dynamic> row) => CourierPayment(
        id: row['id'] as String,
        amount: (row['amount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        note: row['note'] as String?,
      );

  final String id;
  final int amount;
  final DateTime createdAt;
  final String? note;
}

/// A courier, and what they owe. The admin's side of the same account.
@immutable
class CourierBalance {
  const CourierBalance({
    required this.uid,
    required this.name,
    required this.phone,
    required this.owed,
    this.isActive = true,
  });

  factory CourierBalance.fromRow(Map<String, dynamic> row) => CourierBalance(
        uid: row['uid'] as String,
        name: row['name'] as String? ?? '',
        phone: row['phone'] as String? ?? '',
        owed: (row['commission_owed'] as num?)?.toInt() ?? 0,
        isActive: row['is_active'] as bool? ?? true,
      );

  final String uid;
  final String name;
  final String phone;

  /// Positive is owed to the platform. Negative is credit — somebody handed over more
  /// than they owed, which is said in words rather than with a minus sign.
  final int owed;

  final bool isActive;
}

/// What `record_courier_payment` gives back — the whole identity of the receipt, not
/// just a balance.
///
/// A reply that says only «الباقي كذا» cannot be checked against the attempt that asked
/// for it, so a stale pending record and a later collection look identical to the screen
/// reconciling them. In a cash business the receipt is the only evidence there is, so the
/// reply names itself and the screen refuses anything that does not match.
@immutable
class CourierCollection {
  const CourierCollection({
    required this.remaining,
    required this.receiptId,
    required this.courierUid,
    required this.amount,
    required this.repeated,
    this.createdAt,
  });

  factory CourierCollection.fromJson(Map<String, dynamic> json) => CourierCollection(
        remaining: (json['remaining'] as num?)?.toInt() ?? 0,
        receiptId: json['receiptId'] as String?,
        courierUid: json['courierUid'] as String?,
        amount: (json['amount'] as num?)?.toInt(),
        repeated: json['repeated'] as bool? ?? false,
        createdAt: switch (json['createdAt']) {
          final String at => DateTime.tryParse(at)?.toLocal(),
          _ => null,
        },
      );

  /// What the courier still owes, as it stands now.
  final int remaining;

  /// The receipt this reply belongs to. Null only from a server too old to say.
  final String? receiptId;
  final String? courierUid;
  final int? amount;

  /// True when the server had already recorded this receipt and this call changed
  /// nothing. Without it, "the cash was taken" and "the cash had already been taken" are
  /// the same sentence, and only one is true of the tap in front of the operator.
  final bool repeated;

  final DateTime? createdAt;

  /// Whether this reply is an answer to the attempt that was actually sent.
  ///
  /// A server that says nothing about the receipt is trusted, because an older one
  /// cannot be made to say it; a server that names a *different* receipt, courier or
  /// amount is not.
  bool answers({
    required String receiptId,
    required String courierUid,
    required int amount,
  }) =>
      (this.receiptId == null || this.receiptId == receiptId) &&
      (this.courierUid == null || this.courierUid == courierUid) &&
      (this.amount == null || this.amount == amount);
}
