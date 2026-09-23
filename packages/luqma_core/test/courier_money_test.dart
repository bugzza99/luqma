import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Whose money is in the courier's hand.
///
/// The numbers here are the same numbers `supabase/test/local/what_the_courier_keeps`
/// asserts against `apply_courier_settlement`. That is deliberate and it is the whole
/// value of this file: the phone shows the split and the server decides it, so the two
/// have to be told the same sums, and a disagreement has to fail a test rather than turn
/// up in somebody's pocket at the end of a shift.
void main() {
  const address = Address(
    id: 'a1',
    zoneId: 'z1',
    landmarkName: 'صيدلية النور',
    street: 'شارع البحر',
  );

  Order order({
    int subtotal = 10000,
    int deliveryFee = 2000,
    int deliveryDiscount = 0,
    int subtotalDiscount = 0,
    DeliveryBy deliveryBy = DeliveryBy.platform,
  }) =>
      Order(
        id: 'o1',
        cityId: 'edku',
        orderNumber: 101,
        customerName: 'عميل',
        customerPhone: '01000000000',
        merchantId: 'm1',
        merchantName: 'السمك',
        zoneId: 'z1',
        address: address,
        type: OrderType.instant,
        items: const [
          OrderLine(itemId: 'i1', name: 'وجبة', unitPrice: 10000, quantity: 1),
        ],
        pricing: OrderPricing(
          subtotal: subtotal,
          deliveryFee: deliveryFee,
          subtotalDiscount: subtotalDiscount,
          deliveryDiscount: deliveryDiscount,
          total: subtotal - subtotalDiscount + deliveryFee - deliveryDiscount,
        ),
        status: OrderStatus.delivered,
        deliveryBy: deliveryBy,
      );

  group('a platform delivery', () {
    test('splits the cash three ways', () {
      // 100 ج food, 20 ج delivery, 10%: the same order `what_the_courier_keeps` settles.
      final cut = CourierCut.of(order(), onPlatformRoster: true, commissionPercent: 10);

      expect(cut.forShop, 10000);
      expect(cut.forCourier, 1800);
      expect(cut.forPlatform, 200);
      expect(cut.shopSettles, isFalse);
    });

    test('adds back up to the cash actually collected', () {
      // The three figures are a division of one bill, not three independent sums. If they
      // ever stop adding up, a rider hands over the wrong money.
      final placed = order();
      final cut = CourierCut.of(placed, onPlatformRoster: true, commissionPercent: 10);

      expect(cut.forShop + cut.forCourier + cut.forPlatform, placed.pricing.total);
    });

    test('charges nothing on a free delivery', () {
      final cut = CourierCut.of(
        order(deliveryFee: 2000, deliveryDiscount: 2000),
        onPlatformRoster: true, commissionPercent: 10,
      );

      expect(cut.forCourier, 0);
      expect(cut.forPlatform, 0);
      expect(cut.forShop, 10000);
    });

    test('takes a coupon on the food out of the shop\'s share, not the rider\'s', () {
      final cut = CourierCut.of(
        order(subtotalDiscount: 1500),
        onPlatformRoster: true, commissionPercent: 10,
      );

      expect(cut.forShop, 8500);
      expect(cut.forCourier, 1800);
    });

    test('truncates the way Postgres does, never rounds up', () {
      // The server computes `(basis * bps) / 10000` on integers, which truncates. A
      // rounded answer here would put the phone a piastre above the server on half the
      // orders in the city, and the rider would be short at the end of every week.
      final cut = CourierCut.of(order(deliveryFee: 1555), onPlatformRoster: true, commissionPercent: 10);

      expect(cut.forPlatform, 155); // 1555 * 1000 / 10000 = 155.5 -> 155
      expect(cut.forCourier, 1400);
    });

    test('a fractional rate still lands on a whole piastre', () {
      final cut = CourierCut.of(order(deliveryFee: 2000), onPlatformRoster: true, commissionPercent: 7.5);

      expect(cut.forPlatform, 150);
    });

    test('charges nothing at a rate of zero, which is a real setting', () {
      final cut = CourierCut.of(order(), onPlatformRoster: true, commissionPercent: 0);

      expect(cut.forPlatform, 0);
      expect(cut.forCourier, 2000);
    });
  });

  group('a shop delivering with its own rider', () {
    test('hands the shop everything and claims to know nothing else', () {
      // The app has no column for what a shop pays its own courier and does not invent
      // one. A number here would be a guess presented as a fact.
      final cut = CourierCut.of(
        order(deliveryBy: DeliveryBy.merchant),
        onPlatformRoster: true, commissionPercent: 10,
      );

      expect(cut.forShop, 12000);
      expect(cut.forCourier, 0);
      expect(cut.forPlatform, 0);
      expect(cut.shopSettles, isTrue);
    });
  });

  group("a shop's rider carrying a platform order", () {
    test('hands the shop everything, as the server records it', () {
      // E5. `apply_courier_settlement` asks whether the rider is on the platform roster
      // and, when they are not, records `notPlatformCourier` at zero. The screen used to
      // ask only who owned the delivery, and told a shop's rider at the door that 10% of
      // the fee was the platform's and the rest theirs — money the server never counts.
      final cut = CourierCut.of(
        order(),
        onPlatformRoster: false,
        commissionPercent: 10,
      );

      expect(cut.forShop, 12000);
      expect(cut.forCourier, 0);
      expect(cut.forPlatform, 0);
      expect(cut.shopSettles, isTrue);
    });
  });

  group('reading the earnings back', () {
    test('takes the three spans off one answer', () {
      final earnings = CourierEarnings.fromJson(const {
        'today': {
          'delivered': 3, 'returned': 1, 'cash': 36000,
          'fees': 6000, 'commission': 600, 'net': 5400,
        },
        'week': {'delivered': 12, 'returned': 2, 'cash': 140000,
                 'fees': 24000, 'commission': 2400, 'net': 21600},
        'month': {'delivered': 40, 'returned': 5, 'cash': 500000,
                  'fees': 80000, 'commission': 8000, 'net': 72000},
      });

      expect(earnings.today.delivered, 3);
      expect(earnings.today.net, 5400);
      expect(earnings.week.delivered, 12);
      expect(earnings.month.net, 72000);
    });

    test('a span the server did not send is zeros, not a crash', () {
      final earnings = CourierEarnings.fromJson(const {'today': {'delivered': 1}});

      expect(earnings.today.delivered, 1);
      expect(earnings.month, CourierSpan.empty);
      expect(earnings.month.net, 0);
    });

    test('knows when there is nothing to show', () {
      expect(CourierSpan.empty.isEmpty, isTrue);
      expect(const CourierSpan(returned: 1).isEmpty, isFalse);
    });
  });
}
