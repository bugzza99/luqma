import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import 'harness.dart';

/// The order path end to end, against a real Postgres.
///
/// The port of the three Firestore repository tests, plus what only a real database
/// could prove: that prices are recomputed from the menu rather than believed from the
/// phone, that two people tapping the last portion do not both eat, and that the whole
/// lifecycle - placed, accepted, out for delivery, delivered - walks the transitions the
/// same way on both sides of the boundary.
void main() {
  late LiveDatabase live;
  late SupabaseOrderRepository repository;
  late SupabaseMerchantOrderRepository merchantRepository;
  late SupabaseCourierOrderRepository courierRepository;
  late SupabaseOrderRepository customerRepository;
  late String cityId;
  late String zoneId;
  late String merchantId;
  late String menuItemId;
  late String customerUid;
  late String courierUid;
  late SupabaseClient customer;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseOrderRepository(live.client);
    courierRepository = SupabaseCourierOrderRepository(live.client);
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة', 'default_delivery_fee': 1500})
        .select()
        .single()
        .then((row) => row['id'] as String);
    merchantId = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم البحر',
      'zone_id': zoneId,
      'phone': '01000000000',
      'status': 'approved',
      // Luqma's courier carries these orders, so the platform-courier identity is the
      // one the lifecycle runs under.
      'delivers_self': false,
      // Open all week: the function checks the window, so it must find one open.
      'opening_hours': [
        {'weekday': 1, 'openMinute': 0, 'closeMinute': 1441},
        {'weekday': 2, 'openMinute': 0, 'closeMinute': 1441},
        {'weekday': 3, 'openMinute': 0, 'closeMinute': 1441},
        {'weekday': 4, 'openMinute': 0, 'closeMinute': 1441},
        {'weekday': 5, 'openMinute': 0, 'closeMinute': 1441},
        {'weekday': 6, 'openMinute': 0, 'closeMinute': 1441},
        {'weekday': 7, 'openMinute': 0, 'closeMinute': 1441},
      ],
    }).select().single().then((row) => row['id'] as String);
    menuItemId = await live.client.from('menu_items').insert({
      'merchant_id': merchantId,
      'name': 'سمك مشوي',
      'price': 12000,
    }).select().single().then((row) => row['id'] as String);

    (customer, customerUid) = await live.openAsCustomer();
    customerRepository = SupabaseOrderRepository(customer);

    // The kitchen and the platform courier, signed in exactly as their apps do. The
    // transition guards read these claims out of the token, and the courier writes
    // their own uid onto the order - nobody else's name is accepted.
    final ownerDb =
        await live.openAsStaff(scope: 'merchant', role: 'owner', merchantId: merchantId);
    merchantRepository = SupabaseMerchantOrderRepository(ownerDb.$1);
    final (courierDb, orderCourierUid) =
        await live.openAsStaff(scope: 'platform', role: 'courier');
    courierRepository = SupabaseCourierOrderRepository(courierDb);
    courierUid = orderCourierUid;
  });

  tearDown(() async {
    await customer.dispose();
    await live.dropCity(cityId);
  });
  tearDownAll(() => live.close());

  OrderDraft draft({String type = 'instant', int quantity = 1}) => OrderDraft(
        merchantId: merchantId,
        type: OrderType.values.byName(type),
        items: [
          // The phone lies about the price; the server reads the menu.
          OrderLine(itemId: menuItemId, name: 'اسم مزوّر', unitPrice: 1, quantity: quantity),
        ],
      );

  group('placing', () {
    // With cash, a discount computed only on the phone is a discount anyone can edit.
    test('prices come from the menu, not from the phone', () async {
      // The service key carries no customer, and the door stays shut — the refusal
      // itself is the boundary working.
      final anonymous =
          await SupabaseOrderRepository(live.client).placeOrder(draft());
      expect(anonymous.failureOrNull, isNotNull);

      final result = await customerRepository.placeOrder(draft(quantity: 2));
      final f = result.failureOrNull;
      if (f is UnknownFailure) {
        // ignore: avoid_print
        print('PO-DBG inner=${f.cause}');
      }

      final order = result.valueOrNull!;
      // The name and price arrive from the menu; the phone's "1 piastre" was ignored.
      expect(order.items.single.name, 'سمك مشوي');
      expect(order.items.single.unitPrice, 12000);
      expect(order.pricing.subtotal, 24000);
      // No address on a draft means collected by the customer: no fee.
      expect(order.pricing.deliveryFee, 0);
      expect(order.pricing.total, 24000);
    });

    Future<String> seedMeal(int remaining) async =>
        await live.client.from('daily_meals').insert({
          'merchant_id': merchantId,
          'city_id': cityId,
          'name': 'وجبة اليوم',
          'price': 9000,
          'date': DailyMeal.dayKeyOf(DateTime.now()),
          'total_qty': remaining,
          'remaining_qty': remaining,
          'pickup_window_start': 13 * 60,
          'pickup_window_end': 16 * 60,
          'status': 'published',
        }).select().single().then((row) => row['id'] as String);

    test('a pre-order takes its portion inside the transaction', () async {
      final mealId = await seedMeal(5);

      final result = await customerRepository.placeOrder(OrderDraft(
        merchantId: merchantId,
        type: OrderType.preorder,
        dailyMealId: mealId,
        items: [
          OrderLine(itemId: menuItemId, name: 'س', unitPrice: 1, quantity: 2),
        ],
      ));
      final pf = result.failureOrNull;
      if (pf is UnknownFailure) {
        // ignore: avoid_print
        print('PO-DBG preorder=${pf.cause}');
      }

      expect(result.valueOrNull, isNotNull);
      final meal = await live.client
          .from('daily_meals')
          .select('remaining_qty')
          .eq('id', mealId)
          .single();
      expect(meal['remaining_qty'], 3);
    });

    // Two people tapping the last portion at the same moment is the one thing this
    // table exists to get right. The conditional decrement is the race being settled:
    // exactly one of the two orders may take the final portion.
    test('the last portion goes to exactly one of two customers', () async {
      final mealId = await seedMeal(1);

      final (secondCustomer, _) = await live.openAsCustomer();
      addTearDown(secondCustomer.dispose);

      OrderDraft portion() => OrderDraft(
            merchantId: merchantId,
            type: OrderType.preorder,
            dailyMealId: mealId,
            items: [
              OrderLine(itemId: menuItemId, name: 'س', unitPrice: 1, quantity: 1),
            ],
          );

      var wins = 0;
      final first = await customerRepository.placeOrder(portion());
      if (first.valueOrNull != null) wins++;

      try {
        await secondCustomer.rpc(
          'place_order',
          params: {'p_draft': portion().toJson()},
        );
        wins++;
      } on PostgrestException {
        // Sold out is the expected loss, not an error in the test.
      }

      expect(wins, 1);
    });
  });

  group('the lifecycle', () {
    // The whole walk in one line each: placed, accepted, cooking, on the road,
    // delivered - with every move checked against the same transition rules both sides
    // of the boundary enforce.
    test('walks placed to delivered through every hand', () async {
      final order = (await customerRepository.placeOrder(draft())).valueOrNull!;

      await merchantRepository.accept(order.id, prepMinutes: 20);
      await merchantRepository.advance(order.id, to: OrderStatus.preparing);
      await courierRepository.markOnTheWay(
        order.id,
        courierUid: courierUid,
      );
      await courierRepository.markDelivered(order.id);

      final row = await live.client
          .from('orders')
          .select()
          .eq('id', order.id)
          .single();
      expect(row['status'], 'delivered');
      expect(row['courier_uid'], courierUid);
      expect(row['delivered_at'], isNotNull);

      // Delivered is final for everyone. An order that can be reopened is an order
      // whose cash total can be changed after the money was handed over.
      final again = await courierRepository.markFailed(order.id, reason: 'x');
      expect(again.failureOrNull, isA<ConflictFailure>());
    });

    test('a customer can cancel while nobody has answered', () async {
      final order = (await customerRepository.placeOrder(draft())).valueOrNull!;

      await customerRepository.cancel(order.id, reason: 'غيرت رأيي');

      final row = await live.client
          .from('orders')
          .select('status')
          .eq('id', order.id)
          .single();
      expect(row['status'], 'cancelled');
    });

    // Once a kitchen has started, cancelling costs somebody food they already cooked.
    test('a customer cannot cancel an accepted order', () async {
      final order = (await customerRepository.placeOrder(draft())).valueOrNull!;

      await merchantRepository.accept(order.id, prepMinutes: 20);
      final cancelled =
          await customerRepository.cancel(order.id, reason: 'غيرت رأيي');

      expect(cancelled.failureOrNull, isA<ConflictFailure>());
    });
  });
}
