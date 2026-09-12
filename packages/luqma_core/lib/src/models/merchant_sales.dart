import 'package:flutter/foundation.dart';

import 'order.dart';
import '../util/cairo_day.dart';

/// One day of sales in the window.
///
/// Every day of the window is present, including quiet days with zero orders, so a bar
/// chart has no gaps where nothing happened.
@immutable
class MerchantSalesDay {
  const MerchantSalesDay({
    required this.day,
    required this.orders,
    required this.sales,
  });

  /// The date as `YYYY-MM-DD`.
  final String day;

  /// Delivered orders on this day.
  final int orders;

  /// Food sales in integer piastres (`pricing.subtotal`).
  final int sales;

  factory MerchantSalesDay.fromJson(Map<String, dynamic> json) => MerchantSalesDay(
        day: json['day'] as String? ?? '',
        orders: (json['orders'] as num?)?.toInt() ?? 0,
        sales: (json['sales'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'orders': orders,
        'sales': sales,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerchantSalesDay &&
          runtimeType == other.runtimeType &&
          day == other.day &&
          orders == other.orders &&
          sales == other.sales;

  @override
  int get hashCode => Object.hash(day, orders, sales);

  @override
  String toString() => 'MerchantSalesDay($day, orders: $orders, sales: $sales)';
}

/// One dish that sold during the window.
@immutable
class MerchantSalesTopItem {
  const MerchantSalesTopItem({
    required this.itemId,
    required this.name,
    required this.quantity,
  });

  final String itemId;
  final String name;
  final int quantity;

  factory MerchantSalesTopItem.fromJson(Map<String, dynamic> json) =>
      MerchantSalesTopItem(
        itemId: json['itemId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'name': name,
        'quantity': quantity,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerchantSalesTopItem &&
          runtimeType == other.runtimeType &&
          itemId == other.itemId &&
          name == other.name &&
          quantity == other.quantity;

  @override
  int get hashCode => Object.hash(itemId, name, quantity);

  @override
  String toString() => 'MerchantSalesTopItem($name, qty: $quantity)';
}

/// What a shop sold across a window (1..90 days), counted once and in one place.
///
/// Follows the exact semantics of `public.merchant_sales(uuid, integer)`:
/// - Sales are food only (`pricing.subtotal`, integer piastres).
/// - Average is in whole piastres (integer division).
/// - Cancellations are split by who cancelled: customer, merchant, or courier (`returned`).
/// - `byDay` includes every day in chronological order, even empty ones.
/// - `topItems` ranks delivered dishes by quantity descending, then name ascending (up to 5).
@immutable
class MerchantSales {
  const MerchantSales({
    this.days = 7,
    this.orders = 0,
    this.sales = 0,
    this.average = 0,
    this.cancelledByCustomer = 0,
    this.cancelledByMerchant = 0,
    this.returned = 0,
    this.byDay = const [],
    this.topItems = const [],
  });

  /// Window size in days (clamped to 1..90).
  final int days;

  /// Total delivered orders in the window.
  final int orders;

  /// Food sales in integer piastres (sum of subtotals).
  final int sales;

  /// Average order food value in whole piastres (`sales ~/ orders` or 0).
  final int average;

  /// Orders cancelled by the customer.
  final int cancelledByCustomer;

  /// Orders rejected or cancelled by the merchant.
  final int cancelledByMerchant;

  /// Deliveries returned from the door (cancelled by the courier).
  final int returned;

  /// Every day in the window in chronological order.
  final List<MerchantSalesDay> byDay;

  /// Top 5 selling items across delivered orders.
  final List<MerchantSalesTopItem> topItems;

  static const empty = MerchantSales();

  /// Total orders that did not happen: cancelled or returned.
  int get unfulfilled => cancelledByCustomer + cancelledByMerchant + returned;

  factory MerchantSales.fromJson(Map<String, dynamic> json) {
    return MerchantSales(
      days: (json['days'] as num?)?.toInt() ?? 7,
      orders: (json['orders'] as num?)?.toInt() ?? 0,
      sales: (json['sales'] as num?)?.toInt() ?? 0,
      average: (json['average'] as num?)?.toInt() ?? 0,
      cancelledByCustomer: (json['cancelledByCustomer'] as num?)?.toInt() ?? 0,
      cancelledByMerchant: (json['cancelledByMerchant'] as num?)?.toInt() ?? 0,
      returned: (json['returned'] as num?)?.toInt() ?? 0,
      byDay: (json['byDay'] as List<dynamic>?)
              ?.map((e) => MerchantSalesDay.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      topItems: (json['topItems'] as List<dynamic>?)
              ?.map((e) => MerchantSalesTopItem.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'days': days,
        'orders': orders,
        'sales': sales,
        'average': average,
        'cancelledByCustomer': cancelledByCustomer,
        'cancelledByMerchant': cancelledByMerchant,
        'returned': returned,
        'byDay': byDay.map((d) => d.toJson()).toList(),
        'topItems': topItems.map((i) => i.toJson()).toList(),
      };

  /// Computes sales summary in memory from a list of orders.
  ///
  /// Re-applies the exact same rules as the Postgres function `merchant_sales`:
  /// - bounds: `greatest(least(coalesce(days, 7), 90), 1)`
  /// - window is bounded by `after_day` (tomorrow midnight) back by `days`
  /// - delivered orders contribute to `orders`, `sales` and `byDay`
  /// - cancellations split by `cancelledBy`
  /// - top items ordered by quantity desc, then name asc, limit 5
  factory MerchantSales.of(
    Iterable<Order> orders, {
    required String merchantId,
    int days = 7,
    DateTime Function()? now,
  }) {
    final clampedDays = days.clamp(1, 90);
    final current = now?.call() ?? DateTime.now();

    // The window covers [fromAt, toAt) where toAt is tomorrow midnight.
    final todayMidnight = cairoDay(current);
    final afterDay = todayMidnight.add(const Duration(days: 1));
    final fromAt = afterDay.subtract(Duration(days: clampedDays));
    final toAt = afterDay;

    // Pre-populate every day of the series so empty days are represented.
    final byDayMap = <String, ({int orders, int sales})>{};
    for (var i = 0; i < clampedDays; i++) {
      final d = fromAt.add(Duration(days: i));
      final dayStr =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      byDayMap[dayStr] = (orders: 0, sales: 0);
    }

    var totalOrders = 0;
    var totalSales = 0;
    var cancelledByCustomer = 0;
    var cancelledByMerchant = 0;
    var returned = 0;
    final itemQuantities = <(String, String), int>{};

    for (final o in orders) {
      if (o.merchantId != merchantId) continue;
      final placed = o.placedAt;
      if (placed == null) continue;

      final placedNormalized = cairoDay(placed);
      if (placedNormalized.isBefore(fromAt) || !placedNormalized.isBefore(toAt)) {
        continue;
      }

      if (o.status == OrderStatus.delivered) {
        totalOrders++;
        totalSales += o.pricing.subtotal;

        final dayStr =
            '${placedNormalized.year}-${placedNormalized.month.toString().padLeft(2, '0')}-${placedNormalized.day.toString().padLeft(2, '0')}';
        final existing = byDayMap[dayStr];
        if (existing != null) {
          byDayMap[dayStr] = (
            orders: existing.orders + 1,
            sales: existing.sales + o.pricing.subtotal,
          );
        }

        for (final line in o.items) {
          final key = (line.itemId, line.name);
          itemQuantities[key] = (itemQuantities[key] ?? 0) + line.quantity;
        }
      } else if (o.status == OrderStatus.cancelled) {
        if (o.cancelledBy == OrderActor.customer) {
          cancelledByCustomer++;
        } else if (o.cancelledBy == OrderActor.merchant) {
          cancelledByMerchant++;
        } else if (o.cancelledBy == OrderActor.courier) {
          returned++;
        }
      }
    }

    final byDay = byDayMap.entries
        .map((e) => MerchantSalesDay(
              day: e.key,
              orders: e.value.orders,
              sales: e.value.sales,
            ))
        .toList();

    final topItems = itemQuantities.entries.map((e) {
      return MerchantSalesTopItem(
        itemId: e.key.$1,
        name: e.key.$2,
        quantity: e.value,
      );
    }).toList()
      ..sort((a, b) {
        final qtyComp = b.quantity.compareTo(a.quantity);
        if (qtyComp != 0) return qtyComp;
        return a.name.compareTo(b.name);
      });

    final average = totalOrders == 0 ? 0 : totalSales ~/ totalOrders;

    return MerchantSales(
      days: clampedDays,
      orders: totalOrders,
      sales: totalSales,
      average: average,
      cancelledByCustomer: cancelledByCustomer,
      cancelledByMerchant: cancelledByMerchant,
      returned: returned,
      byDay: byDay,
      topItems: topItems.take(5).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerchantSales &&
          runtimeType == other.runtimeType &&
          days == other.days &&
          orders == other.orders &&
          sales == other.sales &&
          average == other.average &&
          cancelledByCustomer == other.cancelledByCustomer &&
          cancelledByMerchant == other.cancelledByMerchant &&
          returned == other.returned &&
          listEquals(byDay, other.byDay) &&
          listEquals(topItems, other.topItems);

  @override
  int get hashCode => Object.hash(
        days,
        orders,
        sales,
        average,
        cancelledByCustomer,
        cancelledByMerchant,
        returned,
        Object.hashAll(byDay),
        Object.hashAll(topItems),
      );

  @override
  String toString() =>
      'MerchantSales(days: $days, orders: $orders, sales: $sales, average: $average)';
}
