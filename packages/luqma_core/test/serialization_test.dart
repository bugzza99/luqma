import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Every model has to serialise into something Firestore will accept.
///
/// This exists because it did not, and nothing caught it. `json_serializable` writes a
/// nested model out as the object itself unless told otherwise — which `jsonEncode`
/// handles on the way past, and Firestore refuses outright. Reads worked perfectly the
/// whole time, so the failure only ever appeared on save.
void main() {
  /// Firestore accepts primitives, lists and maps. Anything else is a model that was
  /// handed over without being converted.
  void expectStorable(Object? value, {String path = ''}) {
    switch (value) {
      case null || String() || num() || bool():
        return;
      case List():
        for (var i = 0; i < value.length; i++) {
          expectStorable(value[i], path: '$path[$i]');
        }
      case Map():
        value.forEach((k, v) => expectStorable(v, path: '$path.$k'));
      default:
        fail('$path is a ${value.runtimeType}, which Firestore cannot store');
    }
  }

  test('a merchant with categories and opening hours', () {
    const merchant = Merchant(
      id: 'm1',
      cityId: 'edku',
      type: MerchantType.restaurant,
      name: 'مطعم',
      zoneId: 'z1',
      phone: '0100',
      openingHours: [OpeningWindow(weekday: 2, openMinute: 720, closeMinute: 1380)],
      menuCategories: [MenuCategory(id: 'c1', name: 'مشويات')],
    );

    expectStorable(merchant.toJson());
  });

  test('an order with line items and pricing', () {
    const order = Order(
      id: 'o1',
      cityId: 'edku',
      orderNumber: 1,
      customerUid: 'u1',
      customerName: 'محمود',
      customerPhone: '0100',
      merchantId: 'm1',
      merchantName: 'مطعم',
      zoneId: 'z1',
      type: OrderType.instant,
      items: [OrderLine(itemId: 'i1', name: 'كشري', unitPrice: 5000, quantity: 2)],
      pricing: OrderPricing(subtotal: 10000, deliveryFee: 1000, total: 11000),
      revenue: RevenueSnapshot(model: RevenueModel.subscription),
    );

    expectStorable(order.toJson());
  });

  test('a menu item with options', () {
    const item = MenuItem(
      id: 'i1',
      merchantId: 'm1',
      categoryId: 'c1',
      name: 'فراخ',
      price: 12000,
      options: [MenuOption(id: 'o1', name: 'كبير', price: 2000)],
    );

    expectStorable(item.toJson());
  });

  test('a coupon, whose dates go through a converter', () {
    final coupon = Coupon(
      id: 'c1',
      code: 'AHLAN',
      cityId: 'edku',
      type: CouponType.percentage,
      value: 1500,
      maxDiscount: 3000,
      validFrom: DateTime(2026, 8, 1),
    );

    // A Timestamp is Firestore's own type, so it is storable even though it is not a
    // primitive — checked separately from the walk above.
    final json = coupon.toJson();
    expect(json['validFrom'], isNotNull);
    expectStorable(Map.of(json)..remove('validFrom')..remove('validUntil'));
  });

  test('an address', () {
    const address = Address(id: 'a1', zoneId: 'z1', landmarkName: 'صيدلية النور');
    expectStorable(address.toJson());
  });

  test('a zone and a landmark', () {
    expectStorable(const Zone(id: 'z1', cityId: 'edku', name: 'المعمورة').toJson());
    expectStorable(
      const Landmark(id: 'l1', cityId: 'edku', zoneId: 'z1', name: 'مسجد').toJson(),
    );
  });
}
