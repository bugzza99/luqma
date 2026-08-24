import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Orders as the person carrying them sees them.
///
/// A third view of the same collection, because a courier asks a third set of questions:
/// what have I got to take out, where does it go, and how much cash do I collect.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreCourierOrderRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreCourierOrderRepository(firestore);
  });

  Future<void> seed({
    String id = 'o1',
    String merchantId = 'm1',
    String cityId = 'edku',
    int orderNumber = 101,
    OrderStatus status = OrderStatus.preparing,
    DeliveryBy deliveryBy = DeliveryBy.merchant,
    String? courierUid,
  }) async {
    await firestore.collection('orders').doc(id).set({
      'cityId': cityId,
      'orderNumber': orderNumber,
      'customerUid': 'u1',
      'customerName': 'أحمد',
      'customerPhone': '01000000000',
      'merchantId': merchantId,
      'merchantName': 'مطعم الشاطئ',
      'zoneId': 'z1',
      'address': const Address(
        id: 'a1',
        zoneId: 'z1',
        landmarkName: 'صيدلية النور',
        building: '12',
      ).toJson(),
      'deliveryBy': deliveryBy.name,
      'type': 'instant',
      'items': [
        const OrderLine(itemId: 'i1', name: 'فراخ', unitPrice: 12000, quantity: 1)
            .toJson(),
      ],
      'pricing': const OrderPricing(
        subtotal: 12000,
        deliveryFee: 1000,
        total: 13000,
      ).toJson(),
      'status': status.name,
      'courierUid': ?courierUid,
    });
  }

  group('a merchant\'s own courier', () {
    test('sees what is ready to go and what is already out', () async {
      await seed(id: 'ready', status: OrderStatus.preparing);
      await seed(id: 'out', status: OrderStatus.outForDelivery, orderNumber: 102);
      await seed(id: 'waiting', status: OrderStatus.placed, orderNumber: 103);
      await seed(id: 'done', status: OrderStatus.delivered, orderNumber: 104);

      final work = await repository.watchForMerchant('m1').first;

      expect(work.map((o) => o.id), containsAll(['ready', 'out']));
      expect(work.map((o) => o.id), isNot(contains('waiting')));
      expect(work.map((o) => o.id), isNot(contains('done')));
    });

    test('never another merchant\'s', () async {
      await seed(id: 'mine', merchantId: 'm1');
      await seed(id: 'theirs', merchantId: 'm2', orderNumber: 102);

      final work = await repository.watchForMerchant('m1').first;

      expect(work.map((o) => o.id), ['mine']);
    });
  });

  group('the platform courier', () {
    test('sees only orders the platform is delivering', () async {
      await seed(id: 'ours', deliveryBy: DeliveryBy.platform);
      await seed(
        id: 'theirs',
        deliveryBy: DeliveryBy.merchant,
        orderNumber: 102,
      );

      final work = await repository.watchForPlatform('edku').first;

      expect(work.map((o) => o.id), ['ours']);
    });

    test('only in this city', () async {
      await seed(id: 'here', deliveryBy: DeliveryBy.platform);
      await seed(
        id: 'elsewhere',
        deliveryBy: DeliveryBy.platform,
        cityId: 'other',
        orderNumber: 102,
      );

      final work = await repository.watchForPlatform('edku').first;

      expect(work.map((o) => o.id), ['here']);
    });
  });

  group('taking an order out', () {
    test('marks it on the way and puts a name to it', () async {
      await seed();

      final result = await repository.markOnTheWay('o1', courierUid: 'c1');

      expect(result.failureOrNull, isNull);
      final order = await repository.watchOrder('o1').first;
      expect(order.status, OrderStatus.outForDelivery);
      // Written at the same moment, because it is what keeps this courier able to read
      // the order afterwards, and what tells the customer who has their food.
      expect(order.courierUid, 'c1');
    });

    test('an order that is not ready yet is refused', () async {
      await seed(status: OrderStatus.accepted);

      final result = await repository.markOnTheWay('o1', courierUid: 'c1');

      expect(result.failureOrNull, isA<ConflictFailure>());
    });
  });

  group('handing it over', () {
    test('delivered is delivered', () async {
      await seed(status: OrderStatus.outForDelivery, courierUid: 'c1');

      await repository.markDelivered('o1');

      final order = await repository.watchOrder('o1').first;
      expect(order.status, OrderStatus.delivered);
      // Stamped, because it is what the revenue engine and every report key off.
      expect(order.deliveredAt, isNotNull);
    });

    // Marking an order delivered before it left is how cash goes missing.
    test('an order still in the kitchen cannot be delivered', () async {
      await seed(status: OrderStatus.preparing);

      final result = await repository.markDelivered('o1');

      expect(result.failureOrNull, isA<ConflictFailure>());
    });

    // Delivered is final. An order that can be reopened is a cash total that can be
    // changed after the money was handed over.
    test('a delivered order cannot be moved again', () async {
      await seed(status: OrderStatus.delivered);

      expect(
        (await repository.markDelivered('o1')).failureOrNull,
        isA<ConflictFailure>(),
      );
    });
  });

  group('a delivery that fails at the door', () {
    // Cash: nobody has paid anything, so a refusal at the door costs the merchant the
    // food. The reason is what feeds the refusal count that eventually blocks somebody.
    test('can be cancelled with a reason', () async {
      await seed(status: OrderStatus.outForDelivery, courierUid: 'c1');

      await repository.markFailed('o1', reason: 'العميل مش موجود');

      final order = await repository.watchOrder('o1').first;
      expect(order.status, OrderStatus.cancelled);
      expect(order.cancelReason, 'العميل مش موجود');
      expect(order.cancelledBy, OrderActor.courier);
    });

    test('needs a reason', () async {
      await seed(status: OrderStatus.outForDelivery);

      final result = await repository.markFailed('o1', reason: '  ');

      expect(result.failureOrNull, isNotNull);
      expect(
        (await repository.watchOrder('o1').first).status,
        OrderStatus.outForDelivery,
      );
    });
  });

  group('the fake', () {
    test('behaves the same way about taking an order out', () async {
      final fake = FakeCourierOrderRepository(seed: [
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
          items: const [
            OrderLine(itemId: 'i1', name: 'فراخ', unitPrice: 12000, quantity: 1),
          ],
          pricing: const OrderPricing(
            subtotal: 12000,
            deliveryFee: 1000,
            total: 13000,
          ),
          status: OrderStatus.preparing,
        ),
      ]);

      await fake.markOnTheWay('o1', courierUid: 'c1');

      expect(fake['o1']!.status, OrderStatus.outForDelivery);
      expect(fake['o1']!.courierUid, 'c1');
    });

    test('reports the failure it was given', () async {
      final fake = FakeCourierOrderRepository(failure: const OfflineFailure());

      expect(
        (await fake.markDelivered('o1')).failureOrNull,
        isA<OfflineFailure>(),
      );
    });
  });
}
