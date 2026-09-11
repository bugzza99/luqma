import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  final row = <String, dynamic>{
    'id': 'o1',
    'city_id': 'edku',
    'order_number': 101,
    'customer_name': 'عميل',
    'customer_phone': '01000000000',
    'merchant_id': 'm1',
    'merchant_name': 'مطعم',
    'zone_id': 'z1',
    'type': 'instant',
    'items': <dynamic>[],
    'pricing': {'subtotal': 10000, 'deliveryFee': 1000, 'total': 11000},
  };

  test('an order note survives column mapping and model serialization', () {
    final order = Order.fromJson(ColumnNames.toModel({
      ...row,
      'note': 'من غير شطة',
    }));
    expect(ColumnNames.toRow(order.toJson())['note'], 'من غير شطة');
  });

  test('an older order without a note still decodes', () {
    final order = Order.fromJson(ColumnNames.toModel(row));
    expect(order.toJson()['note'], isNull);
    expect(order.orderNumber, 101);
  });
}
