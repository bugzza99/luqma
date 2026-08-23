import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Orders as the kitchen sees them.
///
/// A different set of questions from the customer's: what is waiting for an answer, what
/// is on the stove, and which of those can move where. Every transition is checked
/// against who is asking, because most of the rules here are about *who*, not *what*.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreMerchantOrderRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreMerchantOrderRepository(firestore);
  });

  const line = OrderLine(itemId: 'i1', name: 'فراخ مشوية', unitPrice: 12000, quantity: 1);

  Future<void> seed({
    String id = 'o1',
    String merchantId = 'm1',
    int orderNumber = 101,
    OrderStatus status = OrderStatus.placed,
    OrderType type = OrderType.instant,
    bool isNewCustomer = false,
  }) async {
    await firestore.collection('orders').doc(id).set({
      'cityId': 'edku',
      'orderNumber': orderNumber,
      'customerUid': 'u1',
      'customerName': 'أحمد',
      'customerPhone': '01000000000',
      'merchantId': merchantId,
      'merchantName': 'مطعم الشاطئ',
      'zoneId': 'z1',
      'type': type.name,
      'items': [line.toJson()],
      'pricing': const OrderPricing(
        subtotal: 12000,
        deliveryFee: 1000,
        total: 13000,
      ).toJson(),
      'status': status.name,
      'isNewCustomer': isNewCustomer,
    });
  }

  group('what is waiting for an answer', () {
    test('only orders nobody has answered yet', () async {
      await seed(id: 'waiting');
      await seed(id: 'cooking', status: OrderStatus.preparing, orderNumber: 102);

      final incoming = await repository.watchIncoming('m1').first;

      expect(incoming.map((o) => o.id), ['waiting']);
    });

    // A merchant seeing another merchant's order is the single worst thing this
    // collection could leak, so it is asserted here as well as in the rules.
    test('never another kitchen\'s', () async {
      await seed(id: 'mine', merchantId: 'm1');
      await seed(id: 'theirs', merchantId: 'm2', orderNumber: 102);

      final incoming = await repository.watchIncoming('m1').first;

      expect(incoming.map((o) => o.id), ['mine']);
    });

    // The one that has been waiting longest is the one about to run out of time.
    test('oldest first', () async {
      await seed(id: 'later', orderNumber: 105);
      await seed(id: 'earlier', orderNumber: 101);

      final incoming = await repository.watchIncoming('m1').first;

      expect(incoming.map((o) => o.id), ['earlier', 'later']);
    });

    // A merchant who never answered still has to see it — it is a customer waiting for
    // food, not a closed case.
    test('an order that timed out is still in front of them', () async {
      await seed(id: 'missed', status: OrderStatus.needsAttention);

      final incoming = await repository.watchIncoming('m1').first;

      expect(incoming.map((o) => o.id), ['missed']);
    });
  });

  group('what is on the stove', () {
    test('everything accepted and not yet finished', () async {
      await seed(id: 'accepted', status: OrderStatus.accepted);
      await seed(id: 'cooking', status: OrderStatus.preparing, orderNumber: 102);
      await seed(id: 'road', status: OrderStatus.outForDelivery, orderNumber: 103);
      await seed(id: 'done', status: OrderStatus.delivered, orderNumber: 104);
      await seed(id: 'waiting', orderNumber: 105);

      final live = await repository.watchLive('m1').first;

      expect(live.map((o) => o.id), containsAll(['accepted', 'cooking', 'road']));
      expect(live.map((o) => o.id), isNot(contains('done')));
      expect(live.map((o) => o.id), isNot(contains('waiting')));
    });
  });

  group('accepting', () {
    test('moves the order and records how long it will take', () async {
      await seed();

      final result = await repository.accept('o1', prepMinutes: 25);

      expect(result.failureOrNull, isNull);
      final order = await repository.watchOrder('o1').first;
      expect(order.status, OrderStatus.accepted);
      expect(order.prepMinutes, 25);
    });

    // A merchant tapping accept on an order the customer cancelled a second ago would
    // otherwise start cooking food nobody is coming for.
    test('an order that is no longer waiting is refused', () async {
      await seed(status: OrderStatus.cancelled);

      final result = await repository.accept('o1', prepMinutes: 25);

      expect(result.failureOrNull, isA<ConflictFailure>());
    });

    // Somebody who let the timer run out can still accept: the food is still wanted,
    // and the alternative is a customer waiting on nothing.
    test('an order that timed out can still be accepted', () async {
      await seed(status: OrderStatus.needsAttention);

      final result = await repository.accept('o1', prepMinutes: 25);

      expect(result.failureOrNull, isNull);
      expect((await repository.watchOrder('o1').first).status, OrderStatus.accepted);
    });

    test('a preparation time out of range is refused before it is written', () async {
      await seed();

      // Zero minutes is a promise nobody can keep, and three hours is a merchant who
      // meant three. Either reaches the customer as a time they will plan around.
      expect((await repository.accept('o1', prepMinutes: 0)).failureOrNull, isNotNull);
      expect((await repository.accept('o1', prepMinutes: 500)).failureOrNull, isNotNull);
      expect((await repository.watchOrder('o1').first).status, OrderStatus.placed);
    });
  });

  group('rejecting', () {
    test('cancels the order and keeps the reason', () async {
      await seed();

      await repository.reject('o1', reason: 'الصنف خلص');

      final order = await repository.watchOrder('o1').first;
      expect(order.status, OrderStatus.cancelled);
      expect(order.cancelReason, 'الصنف خلص');
      // Who cancelled decides who is answerable for it, and it is the reason the
      // customer is told something different from "you cancelled".
      expect(order.cancelledBy, OrderActor.merchant);
    });

    // A cancellation with no reason gives the customer nothing and the admin nothing.
    test('needs a reason', () async {
      await seed();

      final result = await repository.reject('o1', reason: '   ');

      expect(result.failureOrNull, isNotNull);
      expect((await repository.watchOrder('o1').first).status, OrderStatus.placed);
    });
  });

  group('moving an order along', () {
    test('accepted becomes preparing', () async {
      await seed(status: OrderStatus.accepted);

      await repository.advance('o1', to: OrderStatus.preparing);

      expect((await repository.watchOrder('o1').first).status, OrderStatus.preparing);
    });

    test('preparing goes out for delivery', () async {
      await seed(status: OrderStatus.preparing);

      await repository.advance('o1', to: OrderStatus.outForDelivery);

      expect(
        (await repository.watchOrder('o1').first).status,
        OrderStatus.outForDelivery,
      );
    });

    // The courier marks delivery, because the courier is the one standing at the door
    // with the cash. A merchant marking it from the kitchen is a guess.
    test('a merchant cannot mark an order delivered', () async {
      await seed(status: OrderStatus.outForDelivery);

      final result = await repository.advance('o1', to: OrderStatus.delivered);

      expect(result.failureOrNull, isA<ConflictFailure>());
      expect(
        (await repository.watchOrder('o1').first).status,
        OrderStatus.outForDelivery,
      );
    });

    test('an order cannot skip a step', () async {
      await seed(status: OrderStatus.accepted);

      final result = await repository.advance('o1', to: OrderStatus.outForDelivery);

      expect(result.failureOrNull, isA<ConflictFailure>());
    });
  });

  group('the fake', () {
    test('shows what is waiting and accepts it', () async {
      final fake = FakeMerchantOrderRepository(seed: [
        Order(
          id: 'o1',
          cityId: 'edku',
          orderNumber: 101,
          customerUid: 'u1',
          customerName: 'أحمد',
          customerPhone: '0100',
          merchantId: 'm1',
          merchantName: 'مطعم',
          zoneId: 'z1',
          type: OrderType.instant,
          items: const [line],
          pricing: const OrderPricing(subtotal: 12000, deliveryFee: 1000, total: 13000),
        ),
      ]);

      expect((await fake.watchIncoming('m1').first), hasLength(1));

      await fake.accept('o1', prepMinutes: 20);

      expect(await fake.watchIncoming('m1').first, isEmpty);
      expect((await fake.watchLive('m1').first).single.prepMinutes, 20);
    });

    test('reports the failure it was given', () async {
      final fake = FakeMerchantOrderRepository(failure: const OfflineFailure());

      expect(
        (await fake.accept('o1', prepMinutes: 20)).failureOrNull,
        isA<OfflineFailure>(),
      );
    });
  });
}
