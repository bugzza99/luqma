import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The courier's write queue: the one place a tap that dies with the connection is held
/// rather than lost.
///
/// Tested against the real [FakeCourierOrderRepository], which is taken offline and back
/// online — the exact transition the queue exists to survive.
void main() {
  Order order({OrderStatus status = OrderStatus.preparing}) => Order(
        id: 'o1',
        cityId: 'edku',
        orderNumber: 101,
        customerUid: 'u1',
        customerName: 'أحمد محمود',
        customerPhone: '01000000000',
        merchantId: 'm1',
        merchantName: 'مطعم الشاطئ',
        zoneId: 'z1',
        type: OrderType.instant,
        items: const [
          OrderLine(itemId: 'i1', name: 'فراخ مشوية', unitPrice: 12000, quantity: 1),
        ],
        pricing: const OrderPricing(
          subtotal: 12000,
          deliveryFee: 1000,
          total: 13000,
        ),
        status: status,
        courierUid: 'c1',
      );

  test('an offline write is queued, not lost', () async {
    final repo = FakeCourierOrderRepository(seed: [order()]);
    final queue = CourierWriteQueue(repo);
    repo.failure = const OfflineFailure();

    final outcome = await queue.markDelivered('o1');

    expect(outcome, isA<CourierQueued>());
    expect(queue.pendingCount, 1);
    // The order still shows as out: the server has not been told, and the queue is the
    // honest record of that.
    expect(repo['o1']!.status, OrderStatus.preparing);
  });

  test('a non-offline failure is rejected, never queued', () async {
    final repo = FakeCourierOrderRepository(seed: [order()]);
    final queue = CourierWriteQueue(repo);
    repo.failure = const ConflictFailure();

    final outcome = await queue.markDelivered('o1');

    expect(outcome, isA<CourierRejected>());
    expect(queue.pendingCount, 0);
  });

  test('flush replays oldest first and moves the order', () async {
    final repo = FakeCourierOrderRepository(seed: [order()]);
    final queue = CourierWriteQueue(repo);
    repo.failure = const OfflineFailure();

    await queue.markOnTheWay('o1', courierUid: 'c1');
    await queue.markDelivered('o1');
    expect(queue.pendingCount, 2);

    // The connection comes back; both writes go out in order.
    repo.failure = null;
    await queue.flush();

    expect(queue.pendingCount, 0);
    expect(repo['o1']!.status, OrderStatus.delivered);
    expect(repo['o1']!.courierUid, 'c1');
  });

  test('a write that fails offline again stays queued', () async {
    final repo = FakeCourierOrderRepository(seed: [order()]);
    final queue = CourierWriteQueue(repo);
    repo.failure = const OfflineFailure();

    await queue.markDelivered('o1');
    await queue.flush();

    expect(queue.pendingCount, 1, reason: 'still offline, so still queued');
  });

  test('the queue persists through a store, so a restart does not lose the tap', () async {
    final store = InMemoryCourierWriteStore();
    final repo = FakeCourierOrderRepository(
      seed: [order(status: OrderStatus.outForDelivery)],
    );
    repo.failure = const OfflineFailure();

    final first = CourierWriteQueue(repo, store: store);
    await first.markDelivered('o1');
    expect(store.snapshot, hasLength(1));

    // A fresh queue — a new app launch — loads what the old one saved.
    repo.failure = null;
    final second = CourierWriteQueue(repo, store: store);
    await second.load();
    expect(second.pendingCount, 1);

    await second.flush();
    expect(repo['o1']!.status, OrderStatus.delivered);
    expect(store.snapshot, isEmpty);
  });

  test('a failed delivery is queued with its reason intact', () async {
    final repo = FakeCourierOrderRepository(
      seed: [order(status: OrderStatus.outForDelivery)],
    );
    final queue = CourierWriteQueue(repo);
    repo.failure = const OfflineFailure();

    await queue.markFailed('o1', reason: 'العميل مش موجود');

    expect(queue.pending.single.kind, CourierWriteKind.failed);
    expect(queue.pending.single.reason, 'العميل مش موجود');

    repo.failure = null;
    await queue.flush();

    expect(repo['o1']!.status, OrderStatus.cancelled);
    expect(repo['o1']!.cancelReason, 'العميل مش موجود');
  });
}
