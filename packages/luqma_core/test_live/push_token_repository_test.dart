import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// The tokens that make a merchant's phone ring.
///
/// `fcm_tokens` lives on `users`, which is a guarded table: a customer owns their name,
/// their phone and their addresses, and owns none of the columns that describe how the
/// platform sees them. So registering a token is a write into a row a trigger is
/// watching, and "can the app do this at all" is a question only the real database
/// answers — a fake will happily accept a write the guard would refuse.
///
/// The consequence of getting it wrong is quiet, which is the worst kind: no exception a
/// customer ever sees, just a merchant whose phone never rings, on the single feature
/// the merchant app exists for.
void main() {
  late LiveDatabase live;

  setUpAll(() async => live = await LiveDatabase.open());
  tearDownAll(() => live.close());

  Future<List<String>> tokensOf(String uid) async => ((await live.client
              .from('users')
              .select('fcm_tokens')
              .eq('id', uid)
              .single())['fcm_tokens'] as List?)
          ?.cast<String>() ??
      const [];

  test('a customer registers the token their phone was given', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final repository = SupabasePushTokenRepository(customer);

    expect((await repository.register('tok-a')).failureOrNull, isNull);
    expect(await tokensOf(uid), ['tok-a']);
  });

  test('a merchant owner can register one too', () async {
    final cityId = await live.makeCity();
    addTearDown(() => live.dropCity(cityId));
    final zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'منطقة', 'default_delivery_fee': 1500})
        .select()
        .single()
        .then((row) => row['id'] as String);
    final merchantId = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم',
      'zone_id': zoneId,
      'phone': '01000000000',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);

    final (ownerDb, ownerUid) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(ownerDb.dispose);

    // The merchant is the whole point of push in this product. A staff account is an
    // `auth.users` row like any other, so it has a `users` row and a token list — but
    // "of course it does" is exactly the assumption worth checking against the database.
    expect((await SupabasePushTokenRepository(ownerDb).register('tok-shop')).failureOrNull,
        isNull);
    expect(await tokensOf(ownerUid), ['tok-shop']);
  });

  test('registering the same token twice does not queue two alarms', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final repository = SupabasePushTokenRepository(customer);

    await repository.register('tok-same');
    await repository.register('tok-same');

    // A phone that reinstalls gets its old token back from FCM. Appending blindly would
    // ring the same handset twice for one order.
    expect(await tokensOf(uid), ['tok-same']);
  });

  test('a second device is added rather than replacing the first', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final repository = SupabasePushTokenRepository(customer);

    await repository.register('tok-phone');
    await repository.register('tok-tablet');

    // A shop with a phone in the kitchen and a tablet at the till is the ordinary case,
    // not the exotic one.
    expect(await tokensOf(uid), ['tok-phone', 'tok-tablet']);
  });

  test('signing out forgets only that device', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final repository = SupabasePushTokenRepository(customer);

    await repository.register('tok-phone');
    await repository.register('tok-tablet');
    expect((await repository.forget('tok-phone')).failureOrNull, isNull);

    expect(await tokensOf(uid), ['tok-tablet'],
        reason: 'the till does not go quiet because somebody signed out in the kitchen');
  });

  test('forgetting a token that was never there changes nothing', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final repository = SupabasePushTokenRepository(customer);

    await repository.register('tok-real');
    expect((await repository.forget('tok-never')).failureOrNull, isNull);

    expect(await tokensOf(uid), ['tok-real']);
  });

  test('nobody signed in registers nothing, and says so', () async {
    final anon = live.openAnonymously();
    addTearDown(anon.dispose);

    final result = await SupabasePushTokenRepository(anon).register('tok-anon');

    // The token follows the session, not the launch: registering before sign-in wrote
    // into a row that does not exist and was refused silently.
    expect(result.failureOrNull, isA<PermissionFailure>());
  });

  test('the same write cannot smuggle in a column that is not the user\'s', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);

    // Blocked the way the product blocks: `admin_set_customer_blocked`, as an admin.
    // A direct update is refused even to the service role — `guard_columns` lets only a
    // caller `is_admin()` past it, and a service-role token carries no such claim. That
    // is worth knowing on its own: there is exactly one door to this column.
    final admin = await live.openAsAdmin();
    addTearDown(admin.dispose);
    expect((await SupabaseCustomerRepository(admin).setBlocked(uid, blocked: true))
        .failureOrNull, isNull);

    // `fcm_tokens` is on the guarded table's allowed list; `is_blocked` is deliberately
    // not. A customer who could unblock themselves through the same update the push
    // registration uses would make the whole abuse defence decorative.
    var refused = false;
    try {
      await customer
          .from('users')
          .update({'fcm_tokens': ['tok-x'], 'is_blocked': false}).eq('id', uid);
    } catch (_) {
      refused = true;
    }

    final row = await live.client
        .from('users')
        .select('is_blocked')
        .eq('id', uid)
        .single();
    expect(row['is_blocked'], isTrue,
        reason: refused ? 'refused outright' : 'accepted but did not take effect');
  });
}
