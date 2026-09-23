import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// H-02 left a deleted customer's orders with an address of `{"zoneId": …}` and nothing
/// else — the zone because the statements need it, and nothing personal. Every screen
/// that lists orders reads that row: the shop's history, a courier's statement, the
/// admin's customer page. A row that cannot become an [Order] takes the whole list down.
void main() {
  Map<String, dynamic> row(Map<String, dynamic>? address) => {
        'id': 'o1',
        'cityId': 'edku',
        'orderNumber': 7,
        'customerName': 'حساب محذوف',
        'customerPhone': 'حساب محذوف',
        'merchantId': 'm1',
        'merchantName': 'مطعم',
        'zoneId': 'z1',
        'address': address,
        'type': 'instant',
        'items': const [],
        'pricing': const {'subtotal': 1000, 'deliveryFee': 0, 'total': 1000},
        'status': 'delivered',
      };

  test("a deleted customer's order still reads, zone and all", () {
    final order = Order.fromJson(row({'zoneId': 'z1'}));
    expect(order.customerName, 'حساب محذوف');
    expect(order.address?.zoneId, 'z1');
  });

  test('an order with no address at all still reads', () {
    expect(Order.fromJson(row(null)).address, isNull);
  });
}
