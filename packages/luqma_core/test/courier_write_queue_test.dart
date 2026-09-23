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
        if (next.value?.uid == 'fake-uid-01000000001' && !switched.isCompleted) {
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
    expect(second.accountId, 'fake-uid-01000000001');
    expect(second.pending, isEmpty);
    expect(store.snapshotFor('c1'), hasLength(1));
  });

  // GoTrue emits a fresh identity on every token refresh — hourly on its own, and on every
  // resume through `refreshSession()` — and the queue was keyed on the whole identity.
  // Rebuilding it mid-flush meant two queues replaying the same writes, whichever saved
  // last deciding what was on disk, and the red «محصلش» banner vanishing by itself.
  test('a token refresh for the same account keeps the same CourierWriteQueue instance',
      () async {
    final auth = FakeAuthService(
      restoring: const LuqmaIdentity(
        uid: 'c1',
        claims: {'role': 'courier', 'scope': 'merchant', 'merchantId': 'm1'},
      ),
    );
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        courierOrderRepositoryProvider
            .overrideWithValue(FakeCourierOrderRepository(seed: [order()])),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(auth.dispose);

    var emissions = 0;
    final identitySubscription =
        container.listen(currentIdentityProvider, (_, _) => emissions++);
    addTearDown(identitySubscription.close);
    await container.read(currentIdentityProvider.future);

    final first = container.read(courierWriteQueueProvider);
    final before = emissions;
    await auth.refreshSession();
    for (var i = 0; i < 10 && emissions == before; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(emissions, greaterThan(before),
        reason: 'the refresh has to reach the provider, or this proves nothing');

    expect(identical(container.read(courierWriteQueueProvider), first), isTrue);
  });

  test('rejected writes survive a reload from the store', () async {
    final store = InMemoryCourierWriteStore();
    final repo = FakeCourierOrderRepository(
      seed: [order(status: OrderStatus.outForDelivery)],
      courierUid: 'c1',
    )..failure = const OfflineFailure();

    final first = CourierWriteQueue(repo, accountId: 'c1', store: store);
    await first.markDelivered('o1');
    repo.failure = const ConflictFailure();
    await first.flush();
    expect(first.rejected, hasLength(1));

    // The app is killed before the courier has read the banner.
    final second = CourierWriteQueue(repo, accountId: 'c1', store: store);
    await second.load();
    expect(second.rejected.single.orderId, 'o1');
    expect(second.pending, isEmpty);

    // Read, and gone for good — not back again at the next launch.
    await second.clearRejected();
    final third = CourierWriteQueue(repo, accountId: 'c1', store: store);
    await third.load();
    expect(third.rejected, isEmpty);
  });

  // The request committed and the reply died on the way back. `OfflineFailure` queued a
  // write that had already landed, and the replay found the order delivered and called
  // it a conflict: «تحديث محصلش — الأوردر اتغيّر» for a delivery that went through.
  test('a replay of a write that already landed settles instead of rejecting',
      () async {
    final repo = FakeCourierOrderRepository(
      seed: [order(status: OrderStatus.outForDelivery)],
      courierUid: 'c1',
    );
    final wire = _Wire(repo)..dropReplies = true;
    final queue = CourierWriteQueue(wire, accountId: 'c1');

    expect(await queue.markDelivered('o1'), isA<CourierQueued>());
    expect(repo['o1']!.status, OrderStatus.delivered,
        reason: 'the write landed; only the answer was lost');

    wire.dropReplies = false;
    await queue.flush();

    expect(queue.pending, isEmpty);
    expect(queue.rejected, isEmpty);
  });

  // «بدأت التوصيل» queued in a stairwell; at the door there is signal and the courier taps
  // «تم التسليم». Sent at once, it reached an order still `preparing`, was refused, and
  // was not even queued — while the start sat behind it waiting to be replayed.
  test('a delivered tap behind a queued start is queued, and replays after it',
      () async {
    final repo = FakeCourierOrderRepository(seed: [order()], courierUid: 'c1');
    final wire = _Wire(repo);
    final queue = CourierWriteQueue(wire, accountId: 'c1');

    repo.failure = const OfflineFailure();
    await queue.markOnTheWay('o1', courierUid: 'c1');
    repo.failure = null;
    wire.calls.clear();

    // Still no signal at the door: the delivery waits behind the start, and the only
    // thing tried is the start itself — never the delivery ahead of it.
    repo.failure = const OfflineFailure();
    expect(await queue.markDelivered('o1'), isA<CourierQueued>());
    expect(wire.calls, ['onTheWay:o1'], reason: 'nothing overtakes the start');
    expect([for (final w in queue.pending) w.kind],
        [CourierWriteKind.onTheWay, CourierWriteKind.delivered]);

    repo.failure = null;
    wire.calls.clear();
    await queue.flush();

    expect(wire.calls, ['onTheWay:o1', 'delivered:o1']);
    expect(repo['o1']!.status, OrderStatus.delivered);
    expect(queue.pending, isEmpty);
    expect(queue.rejected, isEmpty);
  });

  test('a tap behind a queued start, made with the signal back, sends both at once '
      'and in order', () async {
    final repo = FakeCourierOrderRepository(seed: [order()], courierUid: 'c1');
    final wire = _Wire(repo);
    final queue = CourierWriteQueue(wire, accountId: 'c1');

    repo.failure = const OfflineFailure();
    await queue.markOnTheWay('o1', courierUid: 'c1');
    repo.failure = null;
    wire.calls.clear();

    // The drain may be backed off for minutes; the courier at the door with signal
    // should not be told «هيتبعت أول ما النت يرجع» about a network that is back.
    expect(await queue.markDelivered('o1'), isA<CourierSubmitted>());
    expect(wire.calls, ['onTheWay:o1', 'delivered:o1']);
    expect(repo['o1']!.status, OrderStatus.delivered);
    expect(queue.pending, isEmpty);
    expect(queue.rejected, isEmpty);
  });

  test("a flush that fails offline on an order keeps that order's later writes "
      'queued, in order', () async {
    final repo = FakeCourierOrderRepository(
      seed: [
        order(),
        order(status: OrderStatus.outForDelivery).copyWith(id: 'o2'),
      ],
      courierUid: 'c1',
    );
    final wire = _Wire(repo);
    final queue = CourierWriteQueue(wire, accountId: 'c1');

    repo.failure = const OfflineFailure();
    await queue.markOnTheWay('o1', courierUid: 'c1');
    await queue.markDelivered('o1');
    await queue.markDelivered('o2');
    repo.failure = null;
    wire.calls.clear();

    // The connection is back, except that `o1`'s first request dies on the way out. Its
    // delivery, sent next, would reach an order still `preparing`.
    wire.unreachable.add('o1');
    await queue.flush();

    expect(wire.calls, ['onTheWay:o1', 'delivered:o2'],
        reason: "o1's delivery must not be sent ahead of its start");
    expect([for (final w in queue.pending) '${w.kind.name}:${w.orderId}'],
        ['onTheWay:o1', 'delivered:o1']);
    expect(queue.rejected, isEmpty);
    expect(repo['o2']!.status, OrderStatus.delivered);
  });

  // A cold start: the screen asks the queue to load, and the store is still reading when
  // the courier taps. The tap used to find a queue that called itself loaded and held
  // nothing, and went straight to the server past the start stored for the same order.
  group('while the stored writes are still loading', () {
    const storedStart = PendingCourierWrite(
      orderId: 'o1',
      kind: CourierWriteKind.onTheWay,
      courierUid: 'c1',
    );

    Future<_GatedStore> storeHolding(List<PendingCourierWrite> pending) async {
      final store = _GatedStore();
      await store.save(accountId: 'c1', pending: pending, rejected: const []);
      return store;
    }

    test('a tap made while the stored writes are still loading waits for them, and '
        'is queued behind a stored write for the same order', () async {
      final store = await storeHolding([storedStart]);
      final repo = FakeCourierOrderRepository(seed: [order()], courierUid: 'c1');
      final wire = _Wire(repo);
      final queue = CourierWriteQueue(wire, accountId: 'c1', store: store);

      final loading = queue.load();
      final tap = queue.markDelivered('o1');
      await pumpEventQueue();
      expect(wire.calls, isEmpty, reason: 'nothing is sent before the queue is read');

      store.release();
      await loading;
      // The signal is there, so both go now — the stored start first, never overtaken.
      expect(await tap, isA<CourierSubmitted>());
      expect(wire.calls, ['onTheWay:o1', 'delivered:o1'],
          reason: 'nothing overtakes the stored start');
      expect(repo['o1']!.status, OrderStatus.delivered);
      expect(queue.pending, isEmpty);
    });

    test('a save made while loading does not overwrite the stored writes', () async {
      final store = await storeHolding([storedStart]);
      final repo = FakeCourierOrderRepository(
        seed: [order(), order().copyWith(id: 'o2')],
        courierUid: 'c1',
      )..failure = const OfflineFailure();
      final queue = CourierWriteQueue(repo, accountId: 'c1', store: store);

      final loading = queue.load();
      final tap = queue.markDelivered('o2');
      await pumpEventQueue();

      store.release();
      await loading;
      expect(await tap, isA<CourierQueued>());
      expect([for (final w in store.snapshotFor('c1')) '${w.kind.name}:${w.orderId}'],
          ['onTheWay:o1', 'delivered:o2']);
    });

    test('a load that fails is retried on the next use', () async {
      final store = await storeHolding([storedStart]);
      store
        ..failNextLoad = true
        ..release();
      final repo = FakeCourierOrderRepository(seed: [order()], courierUid: 'c1')
        ..failure = const OfflineFailure();
      final queue = CourierWriteQueue(repo, accountId: 'c1', store: store);

      await expectLater(queue.load(), throwsA(isA<StateError>()));

      // The next tap reads the store again rather than trusting a load that never
      // finished — and so neither overtakes the stored start nor saves over it.
      expect(await queue.markDelivered('o1'), isA<CourierQueued>());
      expect([for (final w in queue.pending) w.kind],
          [CourierWriteKind.onTheWay, CourierWriteKind.delivered]);
      expect([for (final w in store.snapshotFor('c1')) w.kind],
          [CourierWriteKind.onTheWay, CourierWriteKind.delivered]);
    });
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

  /// Where an order stands for the courier holding it, which is not always where the
  /// server thinks it is. The queue is the only other thing on the phone that knows.
  group("the courier's own account of an order", () {
    const started = PendingCourierWrite(
      orderId: 'o1',
      kind: CourierWriteKind.onTheWay,
      courierUid: 'c1',
    );
    const done = PendingCourierWrite(
      orderId: 'o1',
      kind: CourierWriteKind.delivered,
    );

    test('with nothing queued it is whatever the server says', () {
      expect(CourierProgress.of('o1', OrderStatus.preparing, const []),
          CourierProgress.toCollect);
      expect(CourierProgress.of('o1', OrderStatus.outForDelivery, const []),
          CourierProgress.onTheRoad);
    });

    // The finding: the run was started with no signal, so the server still says
    // `preparing`, and reading it alone left the delivery with no way to be finished.
    test('a start that has not been sent yet still puts them on the road', () {
      expect(CourierProgress.of('o1', OrderStatus.preparing, const [started]),
          CourierProgress.onTheRoad);
    });

    test('and an end that has not been sent leaves nothing more to tap', () {
      expect(CourierProgress.of('o1', OrderStatus.preparing, const [started, done]),
          CourierProgress.finished);
      expect(
          CourierProgress.of('o1', OrderStatus.outForDelivery, const [
            PendingCourierWrite(
                orderId: 'o1',
                kind: CourierWriteKind.failed,
                reason: 'العميل مش موجود'),
          ]),
          CourierProgress.finished);
    });

    test("another order's queue is not this order's business", () {
      expect(
        CourierProgress.of('o2', OrderStatus.preparing, const [started, done]),
        CourierProgress.toCollect,
      );
      expect(lastQueuedFor('o2', const [started, done]), isNull);
    });
  });

  /// A write that finds the order already where it would put it, because this same
  /// courier put it there, is the reply that was lost — not somebody else's move.
  group('a write that already landed', () {
    Order at(OrderStatus status, {String? courierUid = 'c1'}) =>
        order(status: status).copyWith(courierUid: courierUid);

    test('delivered again by the courier carrying it is success', () async {
      final repo = FakeCourierOrderRepository(
        seed: [at(OrderStatus.delivered)],
        courierUid: 'c1',
      );
      expect((await repo.markDelivered('o1')).isOk, isTrue);
    });

    test("a shop's rider on an order nobody's name went out on is the carrier",
        () async {
      final repo = FakeCourierOrderRepository(
        seed: [at(OrderStatus.delivered, courierUid: null)],
        courierUid: 'c1',
      );
      expect((await repo.markDelivered('o1')).isOk, isTrue);
    });

    test('delivered by another courier is still a conflict', () async {
      final repo = FakeCourierOrderRepository(
        seed: [at(OrderStatus.delivered, courierUid: 'c2')],
        courierUid: 'c1',
      );
      expect((await repo.markDelivered('o1')).failureOrNull, isA<ConflictFailure>());
    });

    test('out with this courier on it is success; with another it is not', () async {
      final repo = FakeCourierOrderRepository(
        seed: [at(OrderStatus.outForDelivery)],
        courierUid: 'c1',
      );
      expect((await repo.markOnTheWay('o1', courierUid: 'c1')).isOk, isTrue);
      expect((await repo.markOnTheWay('o1', courierUid: 'c2')).failureOrNull,
          isA<ConflictFailure>());
    });

    test('a return the courier recorded is success; one somebody else did is not',
        () async {
      final returned = FakeCourierOrderRepository(
        seed: [
          at(OrderStatus.cancelled).copyWith(cancelledBy: OrderActor.courier),
        ],
        courierUid: 'c1',
      );
      expect((await returned.markFailed('o1', reason: 'مفيش حد')).isOk, isTrue);

      final byTheShop = FakeCourierOrderRepository(
        seed: [
          at(OrderStatus.cancelled).copyWith(cancelledBy: OrderActor.merchant),
        ],
        courierUid: 'c1',
      );
      expect((await byTheShop.markFailed('o1', reason: 'مفيش حد')).failureOrNull,
          isA<ConflictFailure>());
    });

    test('a different ending is a conflict, whoever wrote it', () async {
      final repo = FakeCourierOrderRepository(
        seed: [at(OrderStatus.delivered)],
        courierUid: 'c1',
      );
      expect((await repo.markFailed('o1', reason: 'مفيش حد')).failureOrNull,
          isA<ConflictFailure>());
    });
  });
}

/// A store whose reads finish only when the test says so, as a phone's disk does at
/// cold start, and whose next read can be made to fail.
class _GatedStore extends InMemoryCourierWriteStore {
  final _gate = Completer<void>();

  bool failNextLoad = false;

  void release() => _gate.complete();

  @override
  Future<StoredCourierWrites> load({required String accountId}) async {
    await _gate.future;
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('the disk could not be read');
    }
    return super.load(accountId: accountId);
  }
}

/// The wire between the queue and a [FakeCourierOrderRepository]: records what was
/// sent, and can lose the reply after the write has landed, or fail a whole order's
/// requests as a dead connection would.
class _Wire implements CourierOrderRepository {
  _Wire(this._real);

  final FakeCourierOrderRepository _real;

  /// Every write the queue sent, as `kind:orderId`, whether or not it arrived.
  final calls = <String>[];

  /// The write goes through and its answer never comes back.
  bool dropReplies = false;

  /// Orders whose next request dies before reaching anything. One request each: the
  /// signal drops for one attempt and is back for the next.
  final unreachable = <String>{};

  Future<Result<void>> _send(
    String kind,
    String orderId,
    Future<Result<void>> Function() write,
  ) async {
    calls.add('$kind:$orderId');
    if (unreachable.remove(orderId)) return const Result.err(OfflineFailure());
    final result = await write();
    if (dropReplies) return const Result.err(OfflineFailure());
    return result;
  }

  @override
  Future<Result<void>> markOnTheWay(String orderId, {required String courierUid}) =>
      _send('onTheWay', orderId,
          () => _real.markOnTheWay(orderId, courierUid: courierUid));

  @override
  Future<Result<void>> markDelivered(String orderId) =>
      _send('delivered', orderId, () => _real.markDelivered(orderId));

  @override
  Future<Result<void>> markFailed(String orderId, {required String reason}) =>
      _send('failed', orderId, () => _real.markFailed(orderId, reason: reason));

  @override
  Stream<List<Order>> watchForMerchant(String merchantId) =>
      _real.watchForMerchant(merchantId);

  @override
  Stream<List<Order>> watchForPlatform(String cityId) => _real.watchForPlatform(cityId);

  @override
  Stream<List<Order>> watchCarried() => _real.watchCarried();

  @override
  Stream<List<String?>> watchCarriedMerchants() => _real.watchCarriedMerchants();

  @override
  Stream<Order> watchOrder(String orderId) => _real.watchOrder(orderId);

  @override
  Future<Result<CourierEarnings>> earnings() => _real.earnings();

  @override
  Future<Result<CourierDaySummary>> daySummary({DateTime? day}) =>
      _real.daySummary(day: day);
}
