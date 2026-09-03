import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The order-creation boundary, including the fake screens exercise most often.
void main() {
  OrderDraft draft({String? clientOrderId}) => OrderDraft(
    merchantId: 'merchant-1',
    clientOrderId: clientOrderId,
    type: OrderType.instant,
    items: const [
      OrderLine(itemId: 'item-1', name: 'سمك', unitPrice: 10000, quantity: 1),
    ],
  );

  final responseOrder = {
    'id': 'order-1',
    'city_id': 'edku',
    'order_number': 1001,
    'customer_uid': 'customer-1',
    'customer_name': 'عميل',
    'customer_phone': '01000000000',
    'merchant_id': 'merchant-1',
    'merchant_name': 'مطعم',
    'zone_id': 'zone-1',
    'delivery_by': 'merchant',
    'type': 'instant',
    'items': [
      {
        'itemId': 'item-1',
        'name': 'سمك',
        'unitPrice': 10000,
        'quantity': 1,
        'optionsTotal': 0,
      },
    ],
    'pricing': {
      'subtotal': 10000,
      'deliveryFee': 0,
      'subtotalDiscount': 0,
      'deliveryDiscount': 0,
      'total': 10000,
      'platformOwesMerchant': 0,
    },
    'status': 'placed',
  };

  group('SupabaseOrderRepository.placeOrder', () {
    test(
      'sends the checkout id as both draft data and the RPC argument',
      () async {
        late Map<String, dynamic> body;
        final client = SupabaseClient(
          'https://example.supabase.co',
          'anon-key',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/rest/v1/rpc/place_order');
            body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
            return http.Response(
              jsonEncode(responseOrder),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);

        final result = await SupabaseOrderRepository(client).placeOrder(
          draft(clientOrderId: '11111111-1111-4111-8111-111111111111'),
        );

        expect(result.valueOrNull?.id, 'order-1');
        expect(
          body['p_client_order_id'],
          '11111111-1111-4111-8111-111111111111',
        );
        expect(
          (body['p_draft'] as Map)['clientOrderId'],
          '11111111-1111-4111-8111-111111111111',
        );
      },
    );

    test('omits the new argument for an old-style draft', () async {
      late Map<String, dynamic> body;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          return http.Response(
            jsonEncode(responseOrder),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);

      expect(
        (await SupabaseOrderRepository(client).placeOrder(draft())).valueOrNull,
        isNotNull,
      );
      expect(body.containsKey('p_client_order_id'), isFalse);
      expect((body['p_draft'] as Map).containsKey('clientOrderId'), isFalse);
    });
  });

  group('FakeOrderRepository.placeOrder', () {
    test('the same client id returns the order already made', () async {
      final repository = FakeOrderRepository();
      final first = (await repository.placeOrder(
        draft(clientOrderId: '11111111-1111-4111-8111-111111111111'),
      )).valueOrNull!;
      final retry = (await repository.placeOrder(
        draft(clientOrderId: '11111111-1111-4111-8111-111111111111'),
      )).valueOrNull!;

      expect(retry, first);
      expect(await repository.watchMyOrders('fake-uid').single, [first]);
    });

    test('different client ids make different orders', () async {
      final repository = FakeOrderRepository();
      final first = (await repository.placeOrder(
        draft(clientOrderId: '11111111-1111-4111-8111-111111111111'),
      )).valueOrNull!;
      final second = (await repository.placeOrder(
        draft(clientOrderId: '22222222-2222-4222-8222-222222222222'),
      )).valueOrNull!;

      expect(second.id, isNot(first.id));
      expect(await repository.watchMyOrders('fake-uid').single, hasLength(2));
    });

    test('an omitted client id keeps making orders for old clients', () async {
      final repository = FakeOrderRepository();
      final first = (await repository.placeOrder(draft())).valueOrNull!;
      final second = (await repository.placeOrder(draft())).valueOrNull!;

      expect(second.id, isNot(first.id));
      expect(await repository.watchMyOrders('fake-uid').single, hasLength(2));
    });
  });
}
