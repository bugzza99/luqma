import 'package:flutter/foundation.dart';

import 'order.dart';

/// One shop's portion of what a courier did during a shift.
///
/// A rider freelancing across several shops in Edku needs to settle with each shop
/// separately: how many deliveries for this kitchen, how many orders came back, and how
/// much cash was collected on their behalf.
@immutable
class CourierShopSummary {
  const CourierShopSummary({
    required this.merchantId,
    required this.merchantName,
    this.platform = false,
    this.delivered = 0,
    this.returned = 0,
    this.cash = 0,
  });

  final String merchantId;
  final String merchantName;

  /// Whether any order for this shop was delivered under the platform delivery model.
  final bool platform;

  /// Completed deliveries for this shop.
  final int delivered;

  /// Orders that came back (refused at the door or unreachable) — trips made with
  /// no cash collected.
  final int returned;

  /// Integer piastres collected on behalf of this shop.
  final int cash;

  factory CourierShopSummary.fromJson(Map<String, dynamic> json) {
    return CourierShopSummary(
      merchantId: json['merchantId'] as String? ?? '',
      merchantName: json['merchantName'] as String? ?? '',
      platform: json['platform'] as bool? ?? false,
      delivered: (json['delivered'] as num?)?.toInt() ?? 0,
      returned: (json['returned'] as num?)?.toInt() ?? 0,
      cash: (json['cash'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'merchantId': merchantId,
        'merchantName': merchantName,
        'platform': platform,
        'delivered': delivered,
        'returned': returned,
        'cash': cash,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourierShopSummary &&
          runtimeType == other.runtimeType &&
          merchantId == other.merchantId &&
          merchantName == other.merchantName &&
          platform == other.platform &&
          delivered == other.delivered &&
          returned == other.returned &&
          cash == other.cash;

  @override
  int get hashCode => Object.hash(
        merchantId,
        merchantName,
        platform,
        delivered,
        returned,
        cash,
      );

  @override
  String toString() =>
      'CourierShopSummary($merchantName, delivered: $delivered, returned: $returned, cash: $cash)';
}

/// What a rider did today, across all shops they carry for.
///
/// Plain Dart class following the pattern of `SettlementSummary`. No wage is modelled
/// and none is computed — the courier is paid outside the app, and the screen counts
/// the verifiable facts: completed deliveries, cash in hand, and what came back.
@immutable
class CourierDaySummary {
  const CourierDaySummary({
    this.delivered = 0,
    this.returned = 0,
    this.cash = 0,
    this.shops = const [],
  });

  /// Orders handed over to the customer.
  final int delivered;

  /// Deliveries that came back: courier-cancelled with a reason.
  final int returned;

  /// Total cash in hand across all delivered orders, in integer piastres.
  final int cash;

  /// Per-shop breakdown, sorted by cash descending, then merchant name ascending.
  final List<CourierShopSummary> shops;

  static const empty = CourierDaySummary();

  bool get isEmpty =>
      delivered == 0 && returned == 0 && cash == 0 && shops.isEmpty;

  bool get isNotEmpty => !isEmpty;

  factory CourierDaySummary.fromJson(Map<String, dynamic> json) {
    return CourierDaySummary(
      delivered: (json['delivered'] as num?)?.toInt() ?? 0,
      returned: (json['returned'] as num?)?.toInt() ?? 0,
      cash: (json['cash'] as num?)?.toInt() ?? 0,
      shops: (json['shops'] as List<dynamic>?)
              ?.map((e) => CourierShopSummary.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'delivered': delivered,
        'returned': returned,
        'cash': cash,
        'shops': shops.map((s) => s.toJson()).toList(),
      };

  /// Computes the summary in-memory over a list of orders.
  ///
  /// Re-applies the exact same rules as the Postgres function `courier_day_summary`:
  /// - only completed deliveries count toward `delivered` and `cash`
  /// - only courier-cancelled orders count toward `returned` (and contribute 0 cash)
  /// - customer-cancelled or merchant-cancelled orders contribute nothing
  /// - per-shop rows are aggregated and sorted by cash descending, then merchant name.
  factory CourierDaySummary.of(Iterable<Order> orders) {
    var totalDelivered = 0;
    var totalReturned = 0;
    var totalCash = 0;
    final perShop = <String, _ShopAccumulator>{};

    for (final o in orders) {
      final isDelivered = o.status == OrderStatus.delivered;
      final isReturned = o.status == OrderStatus.cancelled &&
          o.cancelledBy == OrderActor.courier;
      if (!isDelivered && !isReturned) continue;

      final acc = perShop.putIfAbsent(
        o.merchantId,
        () => _ShopAccumulator(
          merchantId: o.merchantId,
          merchantName: o.merchantName,
          platform: o.deliveryBy == DeliveryBy.platform,
        ),
      );

      if (o.deliveryBy == DeliveryBy.platform) {
        acc.platform = true;
      }

      if (isDelivered) {
        totalDelivered++;
        totalCash += o.pricing.total;
        acc.delivered++;
        acc.cash += o.pricing.total;
      } else if (isReturned) {
        totalReturned++;
        acc.returned++;
      }
    }

    final shops = perShop.values
        .map((acc) => CourierShopSummary(
              merchantId: acc.merchantId,
              merchantName: acc.merchantName,
              platform: acc.platform,
              delivered: acc.delivered,
              returned: acc.returned,
              cash: acc.cash,
            ))
        .toList()
      ..sort((a, b) {
        final cashComp = b.cash.compareTo(a.cash);
        if (cashComp != 0) return cashComp;
        return a.merchantName.compareTo(b.merchantName);
      });

    return CourierDaySummary(
      delivered: totalDelivered,
      returned: totalReturned,
      cash: totalCash,
      shops: shops,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourierDaySummary &&
          runtimeType == other.runtimeType &&
          delivered == other.delivered &&
          returned == other.returned &&
          cash == other.cash &&
          listEquals(shops, other.shops);

  @override
  int get hashCode => Object.hash(
        delivered,
        returned,
        cash,
        Object.hashAll(shops),
      );

  @override
  String toString() =>
      'CourierDaySummary(delivered: $delivered, returned: $returned, cash: $cash, shops: $shops)';
}

class _ShopAccumulator {
  _ShopAccumulator({
    required this.merchantId,
    required this.merchantName,
    required this.platform,
  });

  final String merchantId;
  final String merchantName;
  bool platform;
  int delivered = 0;
  int returned = 0;
  int cash = 0;
}
