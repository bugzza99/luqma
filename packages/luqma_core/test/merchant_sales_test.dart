import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  final cairoNow = DateTime(2026, 9, 12, 14, 0); // Saturday 2pm

  OrderLine line(String id, String name, int qty, int price) => OrderLine(
        itemId: id,
        name: name,
        quantity: qty,
        unitPrice: price,
      );

  Order makeOrder({
    required String id,
    String merchantId = 'm1',
    int subtotal = 10000,
    int deliveryFee = 1500,
    OrderStatus status = OrderStatus.delivered,
    OrderActor? cancelledBy,
    DateTime? placedAt,
    List<OrderLine> items = const [],
  }) {
    return Order(
      id: id,
      cityId: 'edku',
      orderNumber: 1,
      customerName: 'عميل',
      customerPhone: '01000000000',
      merchantId: merchantId,
      merchantName: 'مطعم',
      zoneId: 'z1',
      type: OrderType.instant,
      items: items.isEmpty
          ? [line('i1', 'وجبة', 1, subtotal)]
          : items,
      pricing: OrderPricing(
        subtotal: subtotal,
        deliveryFee: deliveryFee,
        total: subtotal + deliveryFee,
      ),
      status: status,
      cancelledBy: cancelledBy,
      placedAt: placedAt ?? cairoNow,
    );
  }

  group('MerchantSales.fromJson', () {
    test('decodes 64-bit numbers safely as num', () {
      final json = {
        'days': 7,
        'orders': 3,
        'sales': 36000,
        'average': 12000,
        'cancelledByCustomer': 1,
        'cancelledByMerchant': 0,
        'returned': 1,
        'byDay': [
          {'day': '2026-09-06', 'orders': 2, 'sales': 30000},
          {'day': '2026-09-07', 'orders': 0, 'sales': 0},
        ],
        'topItems': [
          {'itemId': 'i1', 'name': 'سمك', 'quantity': 4},
        ],
      };

      final sales = MerchantSales.fromJson(json);

      expect(sales.days, 7);
      expect(sales.orders, 3);
      expect(sales.sales, 36000);
      expect(sales.average, 12000);
      expect(sales.cancelledByCustomer, 1);
      expect(sales.cancelledByMerchant, 0);
      expect(sales.returned, 1);
      expect(sales.unfulfilled, 2);
      expect(sales.byDay.length, 2);
      expect(sales.byDay.first.day, '2026-09-06');
      expect(sales.byDay.first.orders, 2);
      expect(sales.byDay.first.sales, 30000);
      expect(sales.topItems.length, 1);
      expect(sales.topItems.first.name, 'سمك');
      expect(sales.topItems.first.quantity, 4);
    });
  });

  group('MerchantSales.of (in-memory computation)', () {
    test('counts delivered food sales only, ignoring delivery fees', () {
      final fish = [line('i1', 'سمك', 2, 5000)];
      final rice = [line('i2', 'رز', 1, 6000)];

      final orders = [
        makeOrder(
          id: 'o1',
          subtotal: 10000,
          deliveryFee: 2000,
          placedAt: cairoNow,
          items: fish,
        ),
        makeOrder(
          id: 'o2',
          subtotal: 20000,
          deliveryFee: 1500,
          placedAt: cairoNow.subtract(const Duration(days: 1)),
          items: fish,
        ),
        makeOrder(
          id: 'o3',
          subtotal: 6000,
          deliveryFee: 1000,
          placedAt: cairoNow.subtract(const Duration(days: 2)),
          items: rice,
        ),
        // Cancelled orders
        makeOrder(
          id: 'o4',
          subtotal: 9000,
          status: OrderStatus.cancelled,
          cancelledBy: OrderActor.customer,
          placedAt: cairoNow,
        ),
        makeOrder(
          id: 'o5',
          subtotal: 9000,
          status: OrderStatus.cancelled,
          cancelledBy: OrderActor.courier,
          placedAt: cairoNow,
        ),
        // Outside the 7-day window (30 days ago)
        makeOrder(
          id: 'o6',
          subtotal: 99000,
          placedAt: cairoNow.subtract(const Duration(days: 30)),
        ),
        // Another shop
        makeOrder(
          id: 'o7',
          merchantId: 'm2',
          subtotal: 77000,
          placedAt: cairoNow,
        ),
      ];

      final sales = MerchantSales.of(
        orders,
        merchantId: 'm1',
        days: 7,
        now: () => cairoNow,
      );

      expect(sales.orders, 3);
      expect(sales.sales, 36000, reason: 'Food only (10000+20000+6000), no delivery fee');
      expect(sales.average, 12000, reason: '36000 ~/ 3');
      expect(sales.cancelledByCustomer, 1);
      expect(sales.cancelledByMerchant, 0);
      expect(sales.returned, 1, reason: 'Courier cancellation counts as returned');
      expect(sales.unfulfilled, 2);

      // byDay must cover all 7 days in order
      expect(sales.byDay.length, 7);
      expect(sales.byDay.where((d) => d.orders > 0).length, 3);
      expect(sales.byDay.where((d) => d.orders == 0).length, 4);
      expect(sales.byDay.last.day, '2026-09-12');
      expect(sales.byDay.first.day, '2026-09-06');

      // Top items
      expect(sales.topItems.length, 2);
      expect(sales.topItems[0].name, 'سمك');
      expect(sales.topItems[0].quantity, 4);
      expect(sales.topItems[1].name, 'رز');
      expect(sales.topItems[1].quantity, 1);
    });

    test('survives an all-zero week without division by zero', () {
      final sales = MerchantSales.of(
        [],
        merchantId: 'm1',
        days: 7,
        now: () => cairoNow,
      );

      expect(sales.orders, 0);
      expect(sales.sales, 0);
      expect(sales.average, 0);
      expect(sales.cancelledByCustomer, 0);
      expect(sales.cancelledByMerchant, 0);
      expect(sales.returned, 0);
      expect(sales.byDay.length, 7);
      for (final d in sales.byDay) {
        expect(d.orders, 0);
        expect(d.sales, 0);
      }
      expect(sales.topItems, isEmpty);
    });

    test('clamps days window to 1..90', () {
      final salesLow = MerchantSales.of([], merchantId: 'm1', days: 0, now: () => cairoNow);
      expect(salesLow.days, 1);
      expect(salesLow.byDay.length, 1);

      final salesHigh = MerchantSales.of([], merchantId: 'm1', days: 120, now: () => cairoNow);
      expect(salesHigh.days, 90);
      expect(salesHigh.byDay.length, 90);
    });
  });

  group('FakeMerchantSalesRepository', () {
    test('computes from seeded orders', () async {
      final orders = [
        makeOrder(id: 'o1', subtotal: 15000, placedAt: cairoNow),
      ];
      final repo = FakeMerchantSalesRepository(seed: orders, now: () => cairoNow);

      final result = await repo.getSales('m1', days: 7);
      expect(result.isOk, isTrue);
      final sales = result.valueOrThrow;
      expect(sales.orders, 1);
      expect(sales.sales, 15000);
    });

    test('returns failure when instructed', () async {
      final repo = FakeMerchantSalesRepository(
        failure: const OfflineFailure(),
        now: () => cairoNow,
      );

      final result = await repo.getSales('m1');
      expect(result is Err, isTrue);
      expect(result.failureOrNull, isA<OfflineFailure>());
    });
  });
}
