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
      // The customer comes from the token, not from the draft.
      expect(order.customerUid, customerUid);
      // The name and price arrive from the menu; the phone's "1 piastre" was ignored.
      expect(order.items.single.name, 'سمك مشوي');
      expect(order.items.single.unitPrice, 12000);
      expect(order.pricing.subtotal, 24000);
      // No address on a draft means collected by the customer: no fee.
      expect(order.pricing.deliveryFee, 0);
      expect(order.pricing.total, 24000);
    });

    // A blocked customer is the whole of the abuse defence, and `users.is_blocked` was
    // written by the admin and read by nobody: nothing in `place_order`, no policy, and
    // not the token hook. The block was a button that would have lied to whoever pressed
    // it, and the customer it blocked would have kept ordering.
    test('a blocked customer is refused', () async {
      // Ordinary first, so the refusal below cannot be some unrelated door being shut.
      expect((await customerRepository.placeOrder(draft())).valueOrNull, isNotNull);

      // Blocked the way an admin blocks: through the production function, so the test
      // proves the whole path rather than a column somebody set by hand.
      final admin = await live.openAsAdmin();
      await admin.rpc('admin_set_customer_blocked',
          params: {'p_uid': customerUid, 'p_blocked': true});

      final blocked = await customerRepository.placeOrder(draft());
      expect(blocked.valueOrNull, isNull, reason: 'a blocked customer must not order');
      expect(blocked.failureOrNull, isA<PermissionFailure>());

      await admin.rpc('admin_set_customer_blocked',
          params: {'p_uid': customerUid, 'p_blocked': false});
      await admin.dispose();
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
          // A window that is open *now*, rather than 13:00–16:00.
          //
          // `launch_fixes` H2 refuses a reservation once the collection window has
          // closed — correctly — so a fixed afternoon window made these tests pass in
          // the morning and fail after four o'clock. Nothing about the transactional
          // decrement they exist to prove has anything to do with the hour.
          //
          // The window itself is covered where it belongs: by the H2 tests, which move
          // the clock on purpose.
          'pickup_window_start': 0,
          'pickup_window_end': 24 * 60 - 1,
          'status': 'published',
        }).select().single().then((row) => row['id'] as String);

    test('a pre-order takes its portion inside the transaction', () async {
      final mealId = await seedMeal(5);

      // Exactly what PreorderCheckoutScreen sends: the daily meal's own id rides in
      // itemId, and the name and price are copies the server must not believe. A draft
      // that priced itself from menu_items would find nothing - a home kitchen's daily
      // meal has no menu_items row to be found under.
      final result = await customerRepository.placeOrder(OrderDraft(
        merchantId: merchantId,
        type: OrderType.preorder,
        dailyMealId: mealId,
        items: [
          OrderLine(
            itemId: mealId,
            name: 'وجبة اليوم',
            unitPrice: 9000,
            quantity: 2,
          ),
        ],
      ));
      final pf = result.failureOrNull;
      if (pf is UnknownFailure) {
        // ignore: avoid_print
        print('PO-DBG preorder=${pf.cause}');
      }

      final order = result.valueOrNull!;
      // Priced from the day's meal, not from what the phone claimed.
      expect(order.items.single.name, 'وجبة اليوم');
      expect(order.items.single.unitPrice, 9000);
      expect(order.items.single.quantity, 2);
      expect(order.pricing.subtotal, 18000);
      expect(order.pricing.total, 18000);

      final meal = await live.client
          .from('daily_meals')
          .select('remaining_qty')
          .eq('id', mealId)
          .single();
      expect(meal['remaining_qty'], 3);
    });

    test('a pre-order refuses an unpublished meal as a conflict', () async {
      final mealId = await seedMeal(5);
      await live.client
          .from('daily_meals')
          .update({'status': 'draft'})
          .eq('id', mealId);

      final result = await customerRepository.placeOrder(OrderDraft(
        merchantId: merchantId,
        type: OrderType.preorder,
        dailyMealId: mealId,
        items: [
          OrderLine(
            itemId: mealId,
            name: 'وجبة اليوم',
            unitPrice: 9000,
            quantity: 1,
          ),
        ],
      ));

      expect(result.failureOrNull, isA<ConflictFailure>());
    });

    test('a pre-order refuses a line of zero or negative quantity', () async {
      final mealId = await seedMeal(5);

      for (final quantity in [0, -3]) {
        final result = await customerRepository.placeOrder(OrderDraft(
          merchantId: merchantId,
          type: OrderType.preorder,
          dailyMealId: mealId,
          items: [
            OrderLine(itemId: mealId, name: 'وجبة اليوم', unitPrice: 9000, quantity: quantity),
          ],
        ));
        expect(result.failureOrNull, isNotNull, reason: 'quantity=$quantity');
      }

      // Nothing was taken from the counter by any refused draft.
      final meal = await live.client
          .from('daily_meals')
          .select('remaining_qty')
          .eq('id', mealId)
          .single();
      expect(meal['remaining_qty'], 5);
    });

    test('an instant order refuses negative extras on a line', () async {
      final result = await customerRepository.placeOrder(OrderDraft(
        merchantId: merchantId,
        type: OrderType.instant,
        items: [
          // The menu says 12000; "extras" worth -11900 would leave one piastre on the
          // bill if the function priced it in.
          OrderLine(
            itemId: menuItemId,
            name: 'سمك مشوي',
            unitPrice: 12000,
            optionsTotal: -11900,
            quantity: 1,
          ),
        ],
      ));

      expect(result.failureOrNull, isNotNull);
    });

    test('a merchant outside its posted hours refuses the order', () async {
      // Seeded closed rather than updated into closure: the column guard rightly
      // refuses to let anyone flip a merchant's hours from outside, including us.
      final closedId = await live.client.from('merchants').insert({
        'city_id': cityId,
        'type': 'restaurant',
        'name': 'مغلق',
        'zone_id': zoneId,
        'phone': '01000000001',
        'status': 'approved',
        'delivers_self': false,
        'opening_hours': <dynamic>[],
      }).select().single().then((row) => row['id'] as String);

      final result = await customerRepository.placeOrder(OrderDraft(
        merchantId: closedId,
        type: OrderType.instant,
        items: [
          OrderLine(
            itemId: menuItemId,
            name: 'سمك مشوي',
            unitPrice: 12000,
            quantity: 1,
          ),
        ],
      ));

      expect(result.failureOrNull, isA<ConflictFailure>());
    });

    test('a prepaid wallet that cannot cover one more fee refuses', () async {
      // Each kitchen gets its own dish: the function prices every line from a menu
      // item belonging to the merchant being ordered from.
      Future<String> prepaidMerchant(int wallet) async {
        final id = await live.client.from('merchants').insert({
          'city_id': cityId,
          'type': 'restaurant',
          'name': wallet >= 1000 ? 'ممول' : 'مفلس',
          'zone_id': zoneId,
          'phone': '01000000002',
          'status': 'approved',
          'delivers_self': false,
          'revenue_model': 'prepaid',
          'revenue_value': 1000,
          'wallet_balance': wallet,
          'opening_hours': [
            for (var d = 1; d <= 7; d++)
              {'weekday': d, 'openMinute': 0, 'closeMinute': 1441},
          ],
        }).select().single().then((row) => row['id'] as String);
        await live.client.from('menu_items').insert({
          'merchant_id': id,
          'name': 'طبق التجار',
          'price': 12000,
        });
        return id;
      }

      Future<String> dishOf(String merchantId) async => live.client
          .from('menu_items')
          .select('id')
          .eq('merchant_id', merchantId)
          .single()
          .then((row) => row['id'] as String);

      // Five hundred against a thousand-fee: the platform would carry this order free.
      final brokeId = await prepaidMerchant(500);
      final broke = await customerRepository.placeOrder(OrderDraft(
        merchantId: brokeId,
        type: OrderType.instant,
        items: [
          OrderLine(
            itemId: await dishOf(brokeId),
            name: 'طبق التجار',
            unitPrice: 12000,
            quantity: 1,
          ),
        ],
      ));
      expect(broke.failureOrNull, isA<ConflictFailure>());

      // Exactly the fee in the wallet: carried.
      final fundedId = await prepaidMerchant(1000);
      final funded = await customerRepository.placeOrder(OrderDraft(
        merchantId: fundedId,
        type: OrderType.instant,
        items: [
          OrderLine(
            itemId: await dishOf(fundedId),
            name: 'طبق التجار',
            unitPrice: 12000,
            quantity: 1,
          ),
        ],
      ));
      expect(funded.valueOrNull, isNotNull);
    });

    test('an unserved zone is refused; a served one carries the fee', () async {
      final addressId = await live.client.from('addresses').insert({
        'user_id': customerUid,
        'zone_id': zoneId,
        'label': 'البيت',
        'street': 'شارع الميناء',
      }).select().single().then((row) => row['id'] as String);
      // Addresses carry no city column, so the city teardown cannot remove them;
      // leaving this one would block the zone delete with a foreign key.
      addTearDown(() =>
          live.client.from('addresses').delete().eq('id', addressId));

      OrderDraft toAddress() => OrderDraft(
            merchantId: merchantId,
            type: OrderType.instant,
            addressId: addressId,
            items: [
              OrderLine(
                itemId: menuItemId,
                name: 'سمك مشوي',
                unitPrice: 12000,
                quantity: 1,
              ),
            ],
          );

      // No served-zones row yet: this kitchen does not reach this street, whatever the
      // phone chose to show.
      final refused = await customerRepository.placeOrder(toAddress());
      expect(refused.failureOrNull, isA<ConflictFailure>());

      await live.client.from('merchant_served_zones').insert({
        'merchant_id': merchantId,
        'zone_id': zoneId,
      });

      final accepted = await customerRepository.placeOrder(toAddress());
      expect(accepted.valueOrNull, isNotNull);
      expect(accepted.valueOrNull!.pricing.deliveryFee, 1500);
      expect(accepted.valueOrNull!.pricing.total, 13500);
    });

    test('the coupon preview prices like the placement will', () async {
      await live.client.from('coupons').insert({
        'city_id': cityId,
        'code': 'PREVIEW10',
        'type': 'percentage',
        'value': 1000,
        'max_discount': 5000,
        'min_order': 20000,
      });

      // Under the coupon's floor: refused, with the reason said.
      final tooSmall = await customerRepository.evaluateCoupon(
        code: 'PREVIEW10',
        merchantId: merchantId,
        subtotal: 12000,
        deliveryFee: 1500,
      );
      expect(
        (tooSmall.valueOrNull as CouponRejected).reason,
        CouponRejection.minOrderNotMet,
      );

      // Over it - and typed in lower case, like a person types. Ten percent of 24000.
      final ok = await customerRepository.evaluateCoupon(
        code: 'preview10',
        merchantId: merchantId,
        subtotal: 24000,
        deliveryFee: 1500,
      );
      final accepted = ok.valueOrNull as CouponAccepted;
      expect(accepted.subtotalDiscount, 2400);
      expect(accepted.deliveryDiscount, 0);
    });

    test('the coupon preview says when a code has expired', () async {
      await live.client.from('coupons').insert({
        'city_id': cityId,
        'code': 'LASTYEAR',
        'type': 'fixedAmount',
        'value': 5000,
        'valid_until':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      });

      final result = await customerRepository.evaluateCoupon(
        code: 'LASTYEAR',
        merchantId: merchantId,
        subtotal: 24000,
        deliveryFee: 1500,
      );

      expect((result.valueOrNull as CouponRejected).reason, CouponRejection.expired);
    });

    test('one coupon with one use lands on exactly one of two orders', () async {
      await live.client.from('coupons').insert({
        'city_id': cityId,
        'code': 'LAUNCH',
        'type': 'fixedAmount',
        'value': 5000,
        'total_limit': 1,
      });

      OrderDraft couponDraft() => OrderDraft(
            merchantId: merchantId,
            type: OrderType.instant,
            items: [
              OrderLine(
                itemId: menuItemId,
                name: 'سمك مشوي',
                unitPrice: 12000,
                quantity: 2,
              ),
            ],
            couponCode: 'LAUNCH',
          );

      final results = await Future.wait([
        customerRepository.placeOrder(couponDraft()),
        customerRepository.placeOrder(couponDraft()),
      ]);

      // Both drafts read used_count = 0 below the limit; only the conditional update
      // serialises them. Exactly one order exists, and the counter says so too.
      final wins = results.where((r) => r.valueOrNull != null).length;
      expect(
        wins,
        1,
        // The failures, not just the count: "expected 1, got 2" says the race was lost
        // and nothing about how, and this test only ever fails in a way somebody has to
        // reason about.
        reason: 'the other outcomes were '
            '${results.map((r) => r.failureOrNull ?? 'placed').toList()}',
      );

      final coupon = await live.client
          .from('coupons')
          .select('used_count')
          .eq('code', 'LAUNCH')
          .single();
      expect(coupon['used_count'], 1);
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
              // The app's own shape: the meal's id in itemId, the meal's price on the
              // line - both ignored by the server, which reads the row it decrements.
              OrderLine(
                itemId: mealId,
                name: 'وجبة اليوم',
                unitPrice: 9000,
                quantity: 1,
              ),
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

    test('cancelling an order that does not exist is a not-found', () async {
      final cancelled = await customerRepository.cancel(
        '00000000-0000-0000-0000-000000000000',
        reason: 'غيرت رأيي',
      );

      expect(cancelled.failureOrNull, isA<NotFoundFailure>());
    });
  });
}
