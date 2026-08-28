import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// The courier's tap surviving a dead connection — against the real database.
///
/// `CourierWriteQueue` exists for one case, and it is the only one in this product where
/// a lost write is lost money: a courier stands in the street, takes cash, taps
/// "delivered", and the request dies. The order is still out as far as the system knows,
/// and the cash is already in somebody's pocket.
///
/// Its own logic is argued with against a fake elsewhere. What a fake cannot answer is
/// whether the *replay* is accepted — a queued write arrives minutes later, out of the
/// order the app made it in, and has to pass the transition guard and the courier's
/// policies exactly as a live tap would. That is this file's only question, and the
/// class had no live coverage at all.
///
/// "Offline" is produced by a wrapper that refuses once and then delegates to the real
/// repository. The refusal is fake; everything the replay then touches is not.
class _OfflineOnce implements CourierOrderRepository {
  _OfflineOnce(this._real);

  final CourierOrderRepository _real;

  /// While true every write is refused the way a dead connection refuses it.
  bool offline = true;

  int attempts = 0;

  Result<void> get _dead => const Result.err(OfflineFailure());

  @override
  Future<Result<void>> markOnTheWay(String orderId, {required String courierUid}) async {
    attempts++;
    if (offline) return _dead;
    return _real.markOnTheWay(orderId, courierUid: courierUid);
  }

  @override
  Future<Result<void>> markDelivered(String orderId) async {
    attempts++;
    if (offline) return _dead;
    return _real.markDelivered(orderId);
  }

  @override
  Future<Result<void>> markFailed(String orderId, {required String reason}) async {
    attempts++;
    if (offline) return _dead;
    return _real.markFailed(orderId, reason: reason);
  }

  @override
  Stream<List<Order>> watchForMerchant(String merchantId) =>
      _real.watchForMerchant(merchantId);

  @override
  Stream<List<Order>> watchForPlatform(String cityId) => _real.watchForPlatform(cityId);

  @override
  Stream<Order> watchOrder(String orderId) => _real.watchOrder(orderId);
}

void main() {
  late LiveDatabase live;
  late String cityId, zoneId, merchantId, menuItemId, courierUid;
  late SupabaseClient customer;
  late SupabaseOrderRepository customerRepository;
  late SupabaseMerchantOrderRepository merchantRepository;
  late SupabaseCourierOrderRepository courierRepository;

  setUpAll(() async => live = await LiveDatabase.open());
  tearDownAll(() => live.close());

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
      // Luqma's courier carries it, so the platform-courier identity is the one that
      // finishes the order.
      'delivers_self': false,
      'opening_hours': [
        for (var d = 1; d <= 7; d++)
          {'weekday': d, 'openMinute': 0, 'closeMinute': 1441},
      ],
    }).select().single().then((row) => row['id'] as String);
    menuItemId = await live.client.from('menu_items').insert({
      'merchant_id': merchantId,
      'name': 'سمك مشوي',
      'price': 12000,
    }).select().single().then((row) => row['id'] as String);

    (customer, _) = await live.openAsCustomer();
    customerRepository = SupabaseOrderRepository(customer);

    final ownerDb =
        await live.openAsStaff(scope: 'merchant', role: 'owner', merchantId: merchantId);
    merchantRepository = SupabaseMerchantOrderRepository(ownerDb.$1);

    final (courierDb, uid) =
        await live.openAsStaff(scope: 'platform', role: 'courier');
    courierRepository = SupabaseCourierOrderRepository(courierDb);
    courierUid = uid;
  });

  tearDown(() async {
    await customer.dispose();
    await live.dropCity(cityId);
  });

  final draft = () => OrderDraft(
        merchantId: merchantId,
        type: OrderType.instant,
        items: [
          OrderLine(
              itemId: menuItemId, name: 'سمك مشوي', unitPrice: 12000, quantity: 1),
        ],
      );

  /// An order carried as far as the courier picking it up.
  Future<String> orderOutForDelivery() async {
    final order = (await customerRepository.placeOrder(draft())).valueOrNull!;
    await merchantRepository.accept(order.id, prepMinutes: 20);
    await merchantRepository.advance(order.id, to: OrderStatus.preparing);
    await courierRepository.markOnTheWay(order.id, courierUid: courierUid);
    return order.id;
  }

  Future<String> statusOf(String orderId) async => await live.client
      .from('orders')
      .select('status')
      .eq('id', orderId)
      .single()
      .then((row) => row['status'] as String);

  test('a delivery tapped with no connection is kept, not lost', () async {
    final orderId = await orderOutForDelivery();
    final flaky = _OfflineOnce(courierRepository);
    final queue = CourierWriteQueue(flaky);
    addTearDown(queue.dispose);

    final outcome = await queue.markDelivered(orderId);

    expect(outcome, isA<CourierQueued>(),
        reason: 'the courier is told it will go when the connection returns');
    expect(queue.pendingCount, 1);
    expect(await statusOf(orderId), 'outForDelivery',
        reason: 'and nothing has reached the database yet');
  });

  test('and it lands for real once the connection comes back', () async {
    final orderId = await orderOutForDelivery();
    final flaky = _OfflineOnce(courierRepository);
    final queue = CourierWriteQueue(flaky);
    addTearDown(queue.dispose);

    await queue.markDelivered(orderId);
    flaky.offline = false;
    await queue.flush();

    expect(queue.pendingCount, 0);
    // The whole point: the replay passed the transition guard and the courier's
    // policies, minutes after the tap, exactly as a live one would have.
    expect(await statusOf(orderId), 'delivered');
    final row = await live.client
        .from('orders')
        .select('delivered_at, courier_uid')
        .eq('id', orderId)
        .single();
    expect(row['delivered_at'], isNotNull, reason: 'the money-moving stamp is there');
    expect(row['courier_uid'], courierUid);
  });

  test('a tap that outlives the app still lands', () async {
    final orderId = await orderOutForDelivery();
    final store = InMemoryCourierWriteStore();

    // The phone is closed with the write still waiting.
    final before = CourierWriteQueue(_OfflineOnce(courierRepository), store: store);
    await before.markDelivered(orderId);
    before.dispose();
    expect(store.snapshot, hasLength(1),
        reason: 'a tap that only lives in memory dies with the process');

    // Opened again, connection back.
    final flaky = _OfflineOnce(courierRepository)..offline = false;
    final after = CourierWriteQueue(flaky, store: store);
    addTearDown(after.dispose);
    await after.load();
    await after.flush();

    expect(await statusOf(orderId), 'delivered');
    expect(store.snapshot, isEmpty);
  });

  test('an order somebody else already finished is refused, not queued for ever',
      () async {
    final orderId = await orderOutForDelivery();
    // Answered on another phone in the shop, or by the deadline task.
    await courierRepository.markDelivered(orderId);

    final queue = CourierWriteQueue(_OfflineOnce(courierRepository)..offline = false);
    addTearDown(queue.dispose);

    final outcome = await queue.markDelivered(orderId);

    expect(outcome, isA<CourierRejected>(),
        reason: 'retrying will not change it, and the courier should be told now');
    expect((outcome as CourierRejected).failure, isA<ConflictFailure>());
    expect(queue.pendingCount, 0);
  });

  test('a failed delivery keeps its reason across the queue', () async {
    final orderId = await orderOutForDelivery();
    final flaky = _OfflineOnce(courierRepository);
    final queue = CourierWriteQueue(flaky);
    addTearDown(queue.dispose);

    await queue.markFailed(orderId, reason: 'محدش رد على الباب');
    flaky.offline = false;
    await queue.flush();

    final row = await live.client
        .from('orders')
        .select('status, cancel_reason, cancelled_by')
        .eq('id', orderId)
        .single();
    expect(row['status'], 'cancelled');
    // The reason is what an admin reads afterwards; a replay that loses it turns a
    // cancelled order into an unexplained one.
    expect(row['cancel_reason'], 'محدش رد على الباب');
    expect(row['cancelled_by'], 'courier');
  });

  test('several taps replay in the order they were made', () async {
    final first = await orderOutForDelivery();
    final second = await orderOutForDelivery();

    final flaky = _OfflineOnce(courierRepository);
    final queue = CourierWriteQueue(flaky);
    addTearDown(queue.dispose);

    await queue.markDelivered(first);
    await queue.markFailed(second, reason: 'العنوان غلط');
    expect(queue.pendingCount, 2);

    flaky.offline = false;
    await queue.flush();

    expect(await statusOf(first), 'delivered');
    expect(await statusOf(second), 'cancelled');
    expect(queue.pendingCount, 0);
  });
  // The hole this file found. A courier taps "delivered" with no signal, the banner
  // promises "هيتبعت أول ما النت يرجع", and meanwhile the order moves — an admin
  // resolving an issue, a second courier, the deadline task. On replay the write is
  // refused, and `flush` drops anything that is not an offline failure.
  //
  // Dropping it is right: retrying a conflict for ever is noise. Dropping it *silently*
  // is not. The count on the banner falls by one, the courier reads that as sent, and
  // the cash in their pocket is against an order the system says nobody delivered.
  test('a queued write refused on replay is reported, not silently dropped', () async {
    final orderId = await orderOutForDelivery();
    final flaky = _OfflineOnce(courierRepository);
    final queue = CourierWriteQueue(flaky);
    addTearDown(queue.dispose);

    await queue.markDelivered(orderId);
    expect(queue.pendingCount, 1);

    // While the courier had no signal, the order was finished by somebody else.
    await courierRepository.markDelivered(orderId);

    flaky.offline = false;
    await queue.flush();

    expect(queue.pendingCount, 0, reason: 'it is not retried for ever');
    expect(queue.rejected, hasLength(1),
        reason: 'but the courier has to be told it never landed');
    expect(queue.rejected.single.orderId, orderId);
    expect(queue.rejected.single.kind, CourierWriteKind.delivered);
  });

  test('and clearing what was reported empties it', () async {
    final orderId = await orderOutForDelivery();
    final flaky = _OfflineOnce(courierRepository);
    final queue = CourierWriteQueue(flaky);
    addTearDown(queue.dispose);

    await queue.markDelivered(orderId);
    await courierRepository.markDelivered(orderId);
    flaky.offline = false;
    await queue.flush();
    expect(queue.rejected, isNotEmpty);

    queue.clearRejected();
    expect(queue.rejected, isEmpty,
        reason: 'the courier has read it; it must not stay on the screen for ever');
  });
}
