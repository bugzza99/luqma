import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// Who can read a settlement, through the query the screen actually runs.
///
/// The policy is the whole of this file. `order_settlements` grants `select` and nothing
/// else, and a merchant sees their own rows only — so the failure mode to guard against
/// is not an error, it is an empty list: a policy that allows less than the query asks
/// for returns nothing rather than refusing, and "you have no charges" is a sentence this
/// product says for real.
void main() {
  late LiveDatabase live;
  late String cityId;
  late String zoneId;
  late String merchantId;
  late String otherMerchantId;
  late String customerUid;

  /// The merchant's own token, and the shop next door's.
  ///
  /// Read through these rather than through the service key, because the service key
  /// bypasses every policy — a suite that only ever uses it proves the *rows* are right
  /// and nothing whatever about who can see them.
  late SupabaseClient ownerDb;
  late SupabaseClient otherOwnerDb;

  /// Luqma's own courier, who is the only one that may mark an order delivered.
  late SupabaseClient courierDb;
  late String courierUid;

  setUpAll(() async {
    live = await LiveDatabase.open();
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'منطقة'})
        .select()
        .single()
        .then((row) => row['id'] as String);

    Future<String> merchant(String name) => live.client.from('merchants').insert({
          'city_id': cityId,
          'type': 'restaurant',
          'name': name,
          'zone_id': zoneId,
          'phone': '01000000000',
          'status': 'approved',
          'revenue_model': 'commission',
          'revenue_value': 1000,
          'delivers_self': false,
          'opening_hours': [
            for (var d = 1; d <= 7; d++)
              {'weekday': d, 'openMinute': 0, 'closeMinute': 1441},
          ],
        }).select().single().then((row) => row['id'] as String);

    merchantId = await merchant('مطعم البحر');
    otherMerchantId = await merchant('مطعم تاني');
    customerUid = await live.makeCustomer();

    (ownerDb, _) = await live.openAsStaff(
      scope: 'merchant', role: 'owner', merchantId: merchantId);
    (otherOwnerDb, _) = await live.openAsStaff(
      scope: 'merchant', role: 'owner', merchantId: otherMerchantId);
    (courierDb, courierUid) =
        await live.openAsStaff(scope: 'platform', role: 'courier');
  });

  tearDown(() async {
    await ownerDb.dispose();
    await otherOwnerDb.dispose();
    await courierDb.dispose();
    await live.dropCity(cityId);
  });
  tearDownAll(() => live.close());

  /// A delivered order for [merchant], settled by the trigger.
  ///
  /// Delivered by a real courier token, not the service key: the service key's token
  /// carries no claims at all, so the transition guard reads the actor as `nobody` and
  /// refuses — which is correct, and is also the production path. It is the path the two
  /// defects in this feature hid behind, so nothing here takes a shortcut around it.
  Future<String> deliveredOrder(String merchant, {int subtotal = 20000}) async {
    final id = await live.client.from('orders').insert({
      'city_id': cityId,
      'customer_uid': customerUid,
      'customer_name': 'عميل',
      'customer_phone': '01000000000',
      'merchant_id': merchant,
      'merchant_name': 'مطعم',
      'zone_id': zoneId,
      'type': 'instant',
      'items': <dynamic>[],
      'pricing': {
        'subtotal': subtotal,
        'deliveryFee': 1000,
        'total': subtotal + 1000,
        'platformOwesMerchant': 0,
      },
      'revenue': {'model': 'commission', 'value': 1000, 'amount': 0},
      'status': 'outForDelivery',
      // The courier's name goes on at insert: `enforce_courier_claim` lets a courier
      // write only their own, and the service key is not them.
      'courier_uid': courierUid,
      'delivery_by': 'platform',
    }).select().single().then((row) => row['id'] as String);

    await courierDb.from('orders').update({'status': 'delivered'}).eq('id', id);
    return id;
  }

  test('a delivered order appears on the statement', () async {
    final orderId = await deliveredOrder(merchantId);

    final repository = SupabaseSettlementRepository(ownerDb);
    final settlements =
        (await repository.forMerchant(merchantId)).valueOrThrow;

    expect(settlements, hasLength(1));
    expect(settlements.single.orderId, orderId);
    expect(settlements.single.model, RevenueModel.commission);
    expect(settlements.single.basis, 20000, reason: 'the food, never the bill');
    expect(settlements.single.amount, 2000);
    expect(settlements.single.isCharged, isTrue);
  });

  test('and it is only this merchant, not the shop next door', () async {
    await deliveredOrder(merchantId);
    await deliveredOrder(otherMerchantId);

    final mine =
        (await SupabaseSettlementRepository(ownerDb).forMerchant(merchantId))
            .valueOrThrow;

    expect(mine, hasLength(1));
    expect(mine.single.merchantId, merchantId);
  });

  // What one merchant is charged is between them and the platform. The `where` above is
  // a narrowing, not a permission — this asks the policy the question directly, by
  // querying somebody else's id through a token that has no business seeing it.
  test('and asking for the shop next door by id returns nothing', () async {
    await deliveredOrder(otherMerchantId);

    final theirs =
        (await SupabaseSettlementRepository(ownerDb).forMerchant(otherMerchantId))
            .valueOrThrow;

    expect(theirs, isEmpty,
        reason: 'a merchant must not be able to read a competitor by guessing an id');

    // And the row does exist — otherwise this passes for the wrong reason.
    final owner = (await SupabaseSettlementRepository(otherOwnerDb)
            .forMerchant(otherMerchantId))
        .valueOrThrow;
    expect(owner, hasLength(1));
  });

  test('newest first, because a statement is read from the top', () async {
    await deliveredOrder(merchantId, subtotal: 10000);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await deliveredOrder(merchantId, subtotal: 30000);

    final repository = SupabaseSettlementRepository(ownerDb);
    final settlements = (await repository.forMerchant(merchantId)).valueOrThrow;

    expect(settlements.map((s) => s.basis), [30000, 10000]);
  });

  test('the summary counts what the rows say', () async {
    await deliveredOrder(merchantId, subtotal: 10000);
    await deliveredOrder(merchantId, subtotal: 30000);

    final repository = SupabaseSettlementRepository(ownerDb);
    final summary = SettlementSummary.of(
      (await repository.forMerchant(merchantId)).valueOrThrow,
    );

    expect(summary.orders, 2);
    expect(summary.taken, 1000 + 3000);
  });

  // A charge taken back stays on the statement, marked, and counts for nothing. The row
  // is not deleted: "charged and then returned" and "never charged" are different
  // answers, and only one of them is something a merchant should have to be told about.
  test('a reversed charge is shown and not counted', () async {
    final orderId = await deliveredOrder(merchantId);
    await live.client.rpc<void>(
      'apply_order_settlement',
      params: {'p_order_id': orderId, 'p_charged': false},
    );

    final repository = SupabaseSettlementRepository(ownerDb);
    final settlements = (await repository.forMerchant(merchantId)).valueOrThrow;

    expect(settlements, hasLength(1), reason: 'the evidence is not deleted');
    expect(settlements.single.isCharged, isFalse);
    expect(SettlementSummary.of(settlements).taken, 0);
  });

  // Not an error, and that is the point worth pinning. A merchant with no delivered
  // orders and a merchant whose rows the policy hides are indistinguishable from here,
  // which is why the query above is run through a real token rather than trusted.
  test('a merchant with nothing delivered sees an empty statement', () async {
    final repository = SupabaseSettlementRepository(ownerDb);

    final settlements = (await repository.forMerchant(merchantId)).valueOrThrow;

    expect(settlements, isEmpty);
  });

  test('the fake sorts and filters the same way the query does', () async {
    final older = OrderSettlement(
      orderId: 'o1',
      merchantId: 'm1',
      model: RevenueModel.commission,
      basis: 10000,
      amount: 1000,
      settledAt: DateTime(2026, 8, 1),
    );
    final newer = older.copyWith(orderId: 'o2', settledAt: DateTime(2026, 8, 20));
    final theirs = older.copyWith(orderId: 'o3', merchantId: 'm2');

    final fake = FakeSettlementRepository(seed: [older, theirs, newer]);
    final mine = (await fake.forMerchant('m1')).valueOrThrow;

    expect(mine.map((s) => s.orderId), ['o2', 'o1'],
        reason: 'a fake that sorts differently lets a screen pass and be wrong live');
  });

  // Taking the money. The charge is half an account; a debt that only grows is a number
  // that eventually stops meaning anything.
  group('collecting it', () {
    test('an admin records a collection and the debt falls', () async {
      await deliveredOrder(merchantId);
      final adminDb = await live.openAsAdmin();
      addTearDown(adminDb.dispose);

      final remaining = (await SupabaseSettlementRepository(adminDb).recordPayment(
        merchantId: merchantId,
        amount: 1500,
        note: 'دفع كاش',
      ))
          .valueOrThrow;

      // The order took 2000; 1500 was handed over.
      expect(remaining, 500);

      final row = await live.client
          .from('merchants')
          .select('commission_owed')
          .eq('id', merchantId)
          .single();
      expect(row['commission_owed'], 500,
          reason: 'the balance the function returned is the balance it wrote');
    });

    test('and the receipt is readable by the merchant it belongs to', () async {
      await deliveredOrder(merchantId);
      final adminDb = await live.openAsAdmin();
      addTearDown(adminDb.dispose);
      await SupabaseSettlementRepository(adminDb)
          .recordPayment(merchantId: merchantId, amount: 1500, note: '  دفع كاش  ');

      final mine = (await SupabaseSettlementRepository(ownerDb)
              .paymentsFor(merchantId))
          .valueOrThrow;

      expect(mine, hasLength(1));
      expect(mine.single.amount, 1500);
      expect(mine.single.note, 'دفع كاش', reason: 'trimmed by the server, not the phone');
    });

    // A merchant who could record their own collections would have free service, for
    // ever. The refusal is the database's, not this interface's.
    test('a merchant owner cannot clear their own debt', () async {
      await deliveredOrder(merchantId);

      final refused = await SupabaseSettlementRepository(ownerDb)
          .recordPayment(merchantId: merchantId, amount: 99999);

      expect(refused.failureOrNull, isA<PermissionFailure>());
      final row = await live.client
          .from('merchants')
          .select('commission_owed')
          .eq('id', merchantId)
          .single();
      expect(row['commission_owed'], 2000, reason: 'and nothing moved');
    });

    test('nor read the receipts of the shop next door', () async {
      final adminDb = await live.openAsAdmin();
      addTearDown(adminDb.dispose);
      await SupabaseSettlementRepository(adminDb)
          .recordPayment(merchantId: otherMerchantId, amount: 500);

      final theirs = (await SupabaseSettlementRepository(ownerDb)
              .paymentsFor(otherMerchantId))
          .valueOrThrow;

      expect(theirs, isEmpty);
    });
  });
}
