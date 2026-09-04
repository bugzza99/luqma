import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final queue = CourierWriteQueue(repo, accountId: 'c1');
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
    final queue = CourierWriteQueue(repo, accountId: 'c1');
    repo.failure = const ConflictFailure();

    final outcome = await queue.markDelivered('o1');

    expect(outcome, isA<CourierRejected>());
    expect(queue.pendingCount, 0);
  });

  test('flush replays oldest first and moves the order', () async {
    final repo = FakeCourierOrderRepository(seed: [order()]);
    final queue = CourierWriteQueue(repo, accountId: 'c1');
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
    final queue = CourierWriteQueue(repo, accountId: 'c1');
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

    final first = CourierWriteQueue(repo, accountId: 'c1', store: store);
    await first.markDelivered('o1');
    expect(store.snapshotFor('c1'), hasLength(1));

    // A fresh queue — a new app launch — loads what the old one saved.
    repo.failure = null;
    final second = CourierWriteQueue(repo, accountId: 'c1', store: store);
    await second.load();
    expect(second.pendingCount, 1);

    await second.flush();
    expect(repo['o1']!.status, OrderStatus.delivered);
    expect(store.snapshotFor('c1'), isEmpty);
  });

  test('one account cannot load another account\'s pending writes', () async {
    final store = InMemoryCourierWriteStore();
    final repo = FakeCourierOrderRepository(
      seed: [order(status: OrderStatus.outForDelivery)],
    )..failure = const OfflineFailure();

    final first = CourierWriteQueue(repo, accountId: 'c1', store: store);
    await first.markDelivered('o1');

    final second = CourierWriteQueue(repo, accountId: 'c2', store: store);
    await second.load();

    expect(first.pendingCount, 1);
    expect(second.pending, isEmpty);
    expect(store.snapshotFor('c1'), hasLength(1));
    expect(store.snapshotFor('c2'), isEmpty);
  });

  test('an account change replaces a queue that already loaded', () async {
    final auth = FakeAuthService(
      restoring: const LuqmaIdentity(
        uid: 'c1',
        claims: {'role': 'courier', 'scope': 'merchant', 'merchantId': 'm1'},
      ),
    );
    final store = InMemoryCourierWriteStore();
    final repo = FakeCourierOrderRepository(
      seed: [order(status: OrderStatus.outForDelivery)],
    )..failure = const OfflineFailure();
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        courierOrderRepositoryProvider.overrideWithValue(repo),
        courierWriteStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    final switched = Completer<void>();
    final identitySubscription = container.listen(
      currentIdentityProvider,
      (_, next) {
        if (next.value?.uid == 'fake-uid' && !switched.isCompleted) {
          switched.complete();
        }
      },
    );
    addTearDown(identitySubscription.close);
    await container.read(currentIdentityProvider.future);

    final first = container.read(courierWriteQueueProvider);
    await first.markDelivered('o1');
    expect(first.pendingCount, 1);

    await auth.signOut();
    await auth.signUpWithPhone(
      phone: '01000000001',
      password: 'password',
      name: 'مندوب تاني',
    );
    await switched.future;

    final second = container.read(courierWriteQueueProvider);
    await second.load();

    expect(identical(second, first), isFalse);
    expect(second.accountId, 'fake-uid');
    expect(second.pending, isEmpty);
    expect(store.snapshotFor('c1'), hasLength(1));
  });

  test('a failed delivery is queued with its reason intact', () async {
    final repo = FakeCourierOrderRepository(
      seed: [order(status: OrderStatus.outForDelivery)],
    );
    final queue = CourierWriteQueue(repo, accountId: 'c1');
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
