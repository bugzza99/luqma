import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// A tap that arrives while the queue is draining.
///
/// Both halves of this are ordinary: `flush` runs from a connectivity listener, and a
/// courier keeps working while it does. `flush` iterated `_pending` directly and awaited
/// inside the loop, so a write added mid-drain either threw
/// `ConcurrentModificationError` out of `flush` — leaving the queue unpersisted and no
/// change announced — or landed after the loop and was thrown away by
/// `_pending..clear()..addAll(remaining)`.
///
/// The second is the loss this class exists to prevent, arriving through the code that
/// prevents it. The count on the courier's screen falls by one and the tap reads as sent.
class _Slow implements CourierOrderRepository {
  _Slow();

  /// Runs once, in the middle of the first write — the moment a tap can land.
  void Function()? duringFirst;

  final done = <String>[];

  Future<Result<void>> _run(String orderId) async {
    final interrupt = duringFirst;
    duringFirst = null;
    // A real write awaits the network; the tap lands in that gap.
    await Future<void>.delayed(Duration.zero);
    interrupt?.call();
    done.add(orderId);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> markDelivered(String orderId, {DateTime? at}) => _run(orderId);

  @override
  Future<Result<void>> markOnTheWay(String orderId, {required String courierUid}) =>
      _run(orderId);

  @override
  Future<Result<void>> markFailed(String orderId, {required String reason}) =>
      _run(orderId);

  @override
  Stream<List<Order>> watchForMerchant(String merchantId) => const Stream.empty();

  @override
  Stream<List<Order>> watchForPlatform(String cityId) => const Stream.empty();

  @override
  Stream<List<Order>> watchCarried() => const Stream.empty();

  @override
  Stream<List<String?>> watchCarriedMerchants() => const Stream.empty();

  @override
  Stream<Order> watchOrder(String orderId) => const Stream.empty();

  @override
  Future<Result<CourierEarnings>> earnings() async =>
      const Result.ok(CourierEarnings.empty);

  @override
  Future<Result<CourierDaySummary>> daySummary({DateTime? day}) async =>
      const Result.ok(CourierDaySummary.empty);
}

/// Refuses everything as a dead connection, so writes queue rather than send.
class _Dead implements CourierOrderRepository {
  @override
  Future<Result<void>> markDelivered(String orderId, {DateTime? at}) async =>
      const Result.err(OfflineFailure());

  @override
  Future<Result<void>> markOnTheWay(String orderId, {required String courierUid}) async =>
      const Result.err(OfflineFailure());

  @override
  Future<Result<void>> markFailed(String orderId, {required String reason}) async =>
      const Result.err(OfflineFailure());

  @override
  Stream<List<Order>> watchForMerchant(String merchantId) => const Stream.empty();

  @override
  Stream<List<Order>> watchForPlatform(String cityId) => const Stream.empty();

  @override
  Stream<List<Order>> watchCarried() => const Stream.empty();

  @override
  Stream<List<String?>> watchCarriedMerchants() => const Stream.empty();

  @override
  Stream<Order> watchOrder(String orderId) => const Stream.empty();

  @override
  Future<Result<CourierEarnings>> earnings() async =>
      const Result.ok(CourierEarnings.empty);

  @override
  Future<Result<CourierDaySummary>> daySummary({DateTime? day}) async =>
      const Result.err(OfflineFailure());
}

void main() {
  test('a tap that lands mid-flush is not lost', () async {
    final store = InMemoryCourierWriteStore();

    // Two writes waiting from an evening with no signal.
    final offline = CourierWriteQueue(_Dead(), accountId: 'c1', store: store);
    await offline.markDelivered('o1');
    await offline.markDelivered('o2');
    offline.dispose();
    expect(store.snapshotFor('c1'), hasLength(2));

    final live = _Slow();
    final queue = CourierWriteQueue(live, accountId: 'c1', store: store);
    addTearDown(queue.dispose);
    await queue.load();

    // The courier taps a third order while the first two are going out. The tap is a
    // future of its own — a real one is fire-and-forget from a button — so it is kept
    // and awaited, or the assertion below races it.
    Future<CourierSubmitOutcome>? tap;
    live.duringFirst = () => tap = queue.markDelivered('o3');

    await queue.flush();
    await tap;

    expect(live.done, containsAll(<String>['o1', 'o2']),
        reason: 'the two that were waiting went out');
    // `o3` either went out with them or is still queued — never neither.
    final landed = live.done.contains('o3');
    final queued = queue.pending.any((w) => w.orderId == 'o3');
    expect(landed || queued, isTrue,
        reason: 'a tap that vanishes is cash collected against an order still showing '
            'as out');
  });

  // Not throwing was never the bar. The «حاول تاني» button called `flush` straight past
  // the drain's guard, so a tap during a timer drain made two passes over one snapshot:
  // every write sent twice, and the second copy of each refused as a conflict and shown
  // to the courier as «محصلش» — for deliveries that had landed.
  test('two concurrent flushes send each write once', () async {
    final store = InMemoryCourierWriteStore();
    final offline = CourierWriteQueue(_Dead(), accountId: 'c1', store: store);
    await offline.markDelivered('o1');
    await offline.markDelivered('o2');
    offline.dispose();

    final server = _Counting({'o1': OrderStatus.outForDelivery, 'o2': OrderStatus.outForDelivery});
    final queue = CourierWriteQueue(server, accountId: 'c1', store: store);
    addTearDown(queue.dispose);
    await queue.load();

    // A connectivity listener that fires twice in quick succession is ordinary, and so is
    // a courier pressing retry while the timer is already draining.
    await Future.wait([queue.flush(), queue.flush()]);

    expect(server.calls, {'o1': 1, 'o2': 1},
        reason: 'one tap is one request, however many flushes overlap');
    expect(queue.pending, isEmpty);
    expect(queue.rejected, isEmpty);
    expect(server.status, {'o1': OrderStatus.delivered, 'o2': OrderStatus.delivered});
  });
}

/// A server that counts every write and applies the courier's transitions, so a second
/// copy of the same delivery is refused the way the database refuses it.
class _Counting extends _Dead {
  _Counting(Map<String, OrderStatus> seed) : status = Map.of(seed);

  final Map<String, OrderStatus> status;
  final calls = <String, int>{};

  @override
  Future<Result<void>> markDelivered(String orderId, {DateTime? at}) async {
    calls[orderId] = (calls[orderId] ?? 0) + 1;
    // The network gap, where an overlapping pass gets its turn.
    await Future<void>.delayed(Duration.zero);
    if (!status[orderId]!.canMoveTo(OrderStatus.delivered, by: OrderActor.courier)) {
      return const Result.err(ConflictFailure());
    }
    status[orderId] = OrderStatus.delivered;
    return const Result.ok(null);
  }
}
