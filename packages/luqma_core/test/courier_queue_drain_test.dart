import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Who sends what the courier queued.
///
/// The queue has always been able to replay; nothing ever asked it to. The only `flush`
/// in the product was a retry button on the courier's screen, so a rider could collect
/// cash at a door, tap delivered with no signal, walk back into coverage, and leave the
/// order unsettled until somebody happened to press that button — under a banner
/// promising «هيتبعت أول ما النت يرجع».
///
/// **Nothing in this file calls `flush`.** That is the point: a test that flushes by hand
/// supplies the very thing the product was missing, which is how the existing recovery
/// test passed against a product that never recovered.
void main() {
  late FakeCourierOrderRepository repo;
  late CourierWriteQueue queue;
  late CourierQueueDrain drain;

  setUp(() {
    repo = FakeCourierOrderRepository(seed: [_order]);
    queue = CourierWriteQueue(repo, accountId: 'courier-1');
  });

  tearDown(() => drain.dispose());

  test('sends a tap made offline, without anybody asking it to', () async {
    repo.failure = const OfflineFailure();
    await queue.markDelivered('o1');
    expect(queue.pending, hasLength(1));

    drain = CourierQueueDrain(queue);
    await drain.start();
    // Still offline, so the first attempt cannot land. The queue must keep it.
    expect(queue.pending, hasLength(1));

    repo.failure = null;

    // The connection comes back and nobody touches the app. Time passes; that is all.
    await Future<void>.delayed(CourierQueueDrain.firstDelay * 1.5);

    expect(queue.pending, isEmpty, reason: 'the tap reached the server on its own');
    // Landed, not dropped. `pending` emptying alone would also be true of a queue that
    // gave up, so the refused pile has to be empty too — that is where a write the server
    // rejected goes, and it exists precisely so nothing disappears in silence.
    expect(queue.rejected, isEmpty);
    // And the order is off the courier's live list, which is what delivering it does.
    final live = await repo.watchForMerchant('m1').first;
    expect(live, isEmpty);
  });

  test('stops asking once there is nothing left to send', () async {
    drain = CourierQueueDrain(queue);
    await drain.start();

    await queue.markDelivered('o1');
    await Future<void>.delayed(CourierQueueDrain.firstDelay * 1.5);
    expect(queue.pending, isEmpty);

    // A drain that keeps waking on an empty queue is a battery a rider notices.
    expect(drain.isWaiting, isFalse);
  });

  test('one drain at a time, because these requests move money', () async {
    repo.failure = const OfflineFailure();
    await queue.markDelivered('o1');
    repo.failure = null;

    drain = CourierQueueDrain(queue);
    // Three at once, as a resume and two timers could overlap.
    await Future.wait([drain.drain(), drain.drain(), drain.drain()]);

    // One tap is one request, however many drains overlap. Two passes over one entry is
    // two requests for one delivery, and these are requests that move money.
    expect(queue.pending, isEmpty);
  });
}

const _order = Order(
  id: 'o1',
  cityId: 'edku',
  orderNumber: 1,
  customerUid: 'c1',
  customerName: 'عميل',
  customerPhone: '01000000000',
  merchantId: 'm1',
  merchantName: 'مطعم',
  zoneId: 'z1',
  type: OrderType.instant,
  items: [],
  pricing: OrderPricing(subtotal: 1000, deliveryFee: 0, total: 1000),
  status: OrderStatus.outForDelivery,
);
