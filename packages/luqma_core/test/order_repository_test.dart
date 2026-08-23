import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Orders, as the customer's phone sees them.
///
/// Placing one is deliberately not a Firestore write: with cash, the total the app shows
/// is the money a person hands over, so the server recomputes it. Everything else here —
/// watching, cancelling, complaining, rating — is an ordinary write the rules police.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreOrderRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreOrderRepository(
      firestore,
      placeOrderCall: (draft) async => throw UnimplementedError(),
    );
  });

  const line = OrderLine(itemId: 'i1', name: 'فراخ مشوية', unitPrice: 12000, quantity: 1);

  Future<String> seedOrder({
    String id = 'o1',
    String customerUid = 'u1',
    OrderStatus status = OrderStatus.placed,
    int orderNumber = 101,
  }) async {
    await firestore.collection('orders').doc(id).set({
      'cityId': 'edku',
      'orderNumber': orderNumber,
      'customerUid': customerUid,
      'customerName': 'أحمد',
      'customerPhone': '01000000000',
      'merchantId': 'm1',
      'merchantName': 'مطعم الشاطئ',
      'zoneId': 'z1',
      'type': 'instant',
      'items': [line.toJson()],
      'pricing': const OrderPricing(
        subtotal: 12000,
        deliveryFee: 1000,
        total: 13000,
      ).toJson(),
      'status': status.name,
    });
    return id;
  }

  group('watching one order', () {
    test('it comes back with its lines intact', () async {
      await seedOrder();

      final order = await repository.watchOrder('o1').first;

      expect(order.merchantName, 'مطعم الشاطئ');
      // The nested list is where a serialization mistake hides: reads work, writes drop.
      expect(order.items.single.name, 'فراخ مشوية');
      expect(order.pricing.total, 13000);
    });

    test('an order that is not there fails rather than hanging', () async {
      expect(repository.watchOrder('nope').first, throwsA(isA<NotFoundFailure>()));
    });
  });

  group('my orders', () {
    test('only mine come back', () async {
      await seedOrder(id: 'o1', customerUid: 'u1');
      await seedOrder(id: 'o2', customerUid: 'u2');

      final orders = await repository.watchMyOrders('u1').first;

      expect(orders.single.id, 'o1');
    });

    // The one being cooked right now is the one being looked for.
    test('the newest is first', () async {
      await seedOrder(id: 'old', orderNumber: 100);
      await seedOrder(id: 'new', orderNumber: 205);

      final orders = await repository.watchMyOrders('u1').first;

      expect(orders.first.id, 'new');
    });
  });

  group('cancelling', () {
    test('a placed order can be cancelled by its customer', () async {
      await seedOrder();

      final result = await repository.cancel('o1', reason: 'غيرت رأيي');

      expect(result.failureOrNull, isNull);
      final order = await repository.watchOrder('o1').first;
      expect(order.status, OrderStatus.cancelled);
      expect(order.cancelledBy, OrderActor.customer);
    });

    // Once a kitchen has started, cancelling costs somebody food they already cooked.
    // The rules refuse it too; refusing here is what stops the button being offered.
    test('an accepted order cannot be cancelled by its customer', () async {
      await seedOrder(status: OrderStatus.accepted);

      final result = await repository.cancel('o1', reason: 'غيرت رأيي');

      expect(result.failureOrNull, isA<ConflictFailure>());
      final order = await repository.watchOrder('o1').first;
      expect(order.status, OrderStatus.accepted);
    });
  });

  group('complaining', () {
    test('an issue is filed against the order and its merchant', () async {
      await seedOrder();

      await repository.raiseIssue(
        orderId: 'o1',
        customerUid: 'u1',
        merchantId: 'm1',
        reason: 'الأكل وصل بارد',
      );

      final issues = await firestore.collection('orderIssues').get();
      expect(issues.docs.single.data()['orderId'], 'o1');
      expect(issues.docs.single.data()['merchantId'], 'm1');
    });
  });

  group('rating', () {
    test('stars and a comment are filed against the order', () async {
      await seedOrder(status: OrderStatus.delivered);

      await repository.rate(
        orderId: 'o1',
        customerUid: 'u1',
        merchantId: 'm1',
        stars: 4,
        comment: 'كان حلو',
      );

      final ratings = await firestore.collection('ratings').get();
      expect(ratings.docs.single.data()['stars'], 4);
    });

    // One rating per order. Rating twice would let one customer move a merchant's
    // average as far as they liked.
    test('rating the same order twice replaces rather than doubles', () async {
      await seedOrder(status: OrderStatus.delivered);

      await repository.rate(
        orderId: 'o1',
        customerUid: 'u1',
        merchantId: 'm1',
        stars: 1,
      );
      await repository.rate(
        orderId: 'o1',
        customerUid: 'u1',
        merchantId: 'm1',
        stars: 5,
      );

      final ratings = await firestore.collection('ratings').get();
      expect(ratings.docs, hasLength(1));
      expect(ratings.docs.single.data()['stars'], 5);
    });
  });

  group('placing', () {
    test('goes through the server, never straight into the collection', () async {
      var called = false;
      final repo = FirestoreOrderRepository(
        firestore,
        placeOrderCall: (draft) async {
          called = true;
          return 'o9';
        },
      );

      await repo.placeOrder(
        const OrderDraft(
          merchantId: 'm1',
          addressId: 'a1',
          items: [line],
          type: OrderType.instant,
        ),
      );

      expect(called, isTrue);
      // A client-written order is a client-chosen price.
      expect((await firestore.collection('orders').get()).docs, isEmpty);
    });

    test('a refused placement comes back as a failure, not an exception', () async {
      final repo = FirestoreOrderRepository(
        firestore,
        placeOrderCall: (draft) async => throw const ConflictFailure(),
      );

      final result = await repo.placeOrder(
        const OrderDraft(
          merchantId: 'm1',
          addressId: 'a1',
          items: [line],
          type: OrderType.instant,
        ),
      );

      expect(result.failureOrNull, isA<ConflictFailure>());
    });
  });

  group('the fake', () {
    test('placing returns an order the customer can then watch', () async {
      final fake = FakeOrderRepository();

      final placed = (await fake.placeOrder(
        const OrderDraft(
          merchantId: 'm1',
          addressId: 'a1',
          items: [line],
          type: OrderType.instant,
        ),
      )).valueOrNull!;

      final watched = await fake.watchOrder(placed.id).first;
      expect(watched.id, placed.id);
    });

    test('reports the failure it was given', () async {
      final fake = FakeOrderRepository(failure: const OfflineFailure());

      final result = await fake.placeOrder(
        const OrderDraft(
          merchantId: 'm1',
          addressId: 'a1',
          items: [line],
          type: OrderType.instant,
        ),
      );

      expect(result.failureOrNull, isA<OfflineFailure>());
    });
  });
}
