import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The address, frozen onto the order.
///
/// Not a reference to `users/{uid}/addresses/{id}`, for two separate reasons and either
/// would be enough. A courier cannot read another person's address collection — the
/// rules see to that — so a reference would render as nothing at the one moment it is
/// needed. And an address corrected next month must not rewrite where last week's order
/// actually went.
void main() {
  const home = Address(
    id: 'a1',
    zoneId: 'z1',
    landmarkId: 'lm1',
    landmarkName: 'صيدلية النور',
    building: '12',
    floor: '3',
    label: 'البيت',
  );

  Order order({Address? address, DeliveryBy deliveryBy = DeliveryBy.merchant}) => Order(
        id: 'o1',
        cityId: 'edku',
        orderNumber: 101,
        customerUid: 'u1',
        customerName: 'أحمد',
        customerPhone: '01000000000',
        merchantId: 'm1',
        merchantName: 'مطعم الشاطئ',
        zoneId: 'z1',
        type: OrderType.instant,
        items: const [
          OrderLine(itemId: 'i1', name: 'فراخ', unitPrice: 12000, quantity: 1),
        ],
        pricing: const OrderPricing(subtotal: 12000, deliveryFee: 1000, total: 13000),
        address: address,
        deliveryBy: deliveryBy,
      );

  group('the address on the order', () {
    test('survives a round trip', () {
      final restored = Order.fromJson(order(address: home).toJson());

      expect(restored.address?.landmarkName, 'صيدلية النور');
      expect(restored.address?.building, '12');
      expect(restored.address?.zoneId, 'z1');
    });

    // The nested-object mistake that reads fine and writes nothing. `explicit_to_json`
    // is what stops it; this is the assertion that would notice if it were ever off.
    test('is written as a map, not as an object nobody can store', () {
      final json = order(address: home).toJson();

      expect(json['address'], isA<Map<String, dynamic>>());
    });

    // Orders placed before this field existed, and any order whose address was somehow
    // lost, still have to open rather than crash a courier's screen.
    test('an order without one still reads', () {
      final restored = Order.fromJson(order().toJson());

      expect(restored.address, isNull);
      expect(restored.zoneId, 'z1');
    });
  });

  group('who delivers it', () {
    // Frozen at order time, not read from the merchant. A merchant who stops delivering
    // their own orders next week must not change who was responsible for last week's.
    test('defaults to the merchant', () {
      expect(order().deliveryBy, DeliveryBy.merchant);
    });

    test('survives a round trip', () {
      final restored =
          Order.fromJson(order(deliveryBy: DeliveryBy.platform).toJson());

      expect(restored.deliveryBy, DeliveryBy.platform);
    });
  });

  group('what a courier reads first', () {
    test('the zone, then the landmark, then the detail', () {
      final line = home.format(zoneName: 'المعمورة');

      expect(line.startsWith('المعمورة'), isTrue);
      expect(line.contains('صيدلية النور'), isTrue);
      expect(line.contains('12'), isTrue);
    });
  });
}
