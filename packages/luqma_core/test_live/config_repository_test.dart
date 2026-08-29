import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// The control plane, against the real table.
///
/// `config` is the one row-store every phone in the city reads on launch: the minimum
/// supported version that walls off old builds, the feature flags, the limits. Two
/// things about it are worth a live test and cannot be asked of a fake.
///
/// The first is that **anybody can read it** — including a phone with nobody signed in.
/// If reading needed a session, the force-update gate would be the thing that fails on
/// exactly the builds it exists to stop, and a new customer's first launch would find no
/// configuration at all.
///
/// The second is that **only an admin can write it**. `min_supported_version` is a wall:
/// set high enough by anyone who could reach it, every app in Edku refuses to start.
void main() {
  late LiveDatabase live;
  late SupabaseClient admin;
  late ConfigRepository repository;

  /// Keys this file owns, so a run cannot disturb the real control plane.
  final owned = <String>[];

  String ownKey(String suffix) {
    final key = 'live_test_${DateTime.now().microsecondsSinceEpoch}_$suffix';
    owned.add(key);
    return key;
  }

  setUpAll(() async {
    live = await LiveDatabase.open();
    admin = await live.openAsAdmin();
    repository = SupabaseConfigRepository(admin);
  });

  tearDownAll(() async {
    if (owned.isNotEmpty) {
      await live.client.from('config').delete().inFilter('key', owned);
    }
    await admin.dispose();
    await live.close();
  });

  test('an admin writes a value and reads it back', () async {
    final key = ownKey('write');

    expect((await repository.setValues({key: 7})).failureOrNull, isNull);

    final all = (await repository.readAll()).valueOrNull!;
    expect(all[key], 7);
  });

  test('writing again replaces rather than duplicating', () async {
    final key = ownKey('replace');

    await repository.setValues({key: 'first'});
    await repository.setValues({key: 'second'});

    expect((await repository.readAll()).valueOrNull![key], 'second');
    // `config.key` is the primary key and the write is an upsert; a second row would be
    // two answers to a question the app asks once.
    final rows = await live.client.from('config').select('key').eq('key', key);
    expect(rows, hasLength(1));
  });

  test('several values land in one call', () async {
    final a = ownKey('multi_a');
    final b = ownKey('multi_b');

    await repository.setValues({a: true, b: 12});

    final all = (await repository.readAll()).valueOrNull!;
    expect(all[a], true);
    expect(all[b], 12);
  });

  test('a phone with nobody signed in can still read the control plane', () async {
    final key = ownKey('anon_read');
    await repository.setValues({key: 'visible'});

    final anon = live.openAnonymously();
    addTearDown(anon.dispose);

    final result = await SupabaseConfigRepository(anon).readAll();

    // The force-update gate runs before sign-in, on the builds it exists to stop.
    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull![key], 'visible');
  });

  test('a customer cannot change what every phone reads', () async {
    final key = ownKey('customer_write');
    await repository.setValues({key: 'admin wrote this'});

    final (customer, _) = await live.openAsCustomer();
    addTearDown(customer.dispose);

    await SupabaseConfigRepository(customer).setValues({key: 'customer wrote this'});

    final row = await live.client
        .from('config')
        .select('value')
        .eq('key', key)
        .single();
    expect(row['value'], 'admin wrote this',
        reason: 'set min_supported_version high enough and every app in the city '
            'refuses to start');
  });

  test('nor can a merchant owner', () async {
    final key = ownKey('owner_write');
    await repository.setValues({key: 'admin wrote this'});

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

    final (ownerDb, _) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(ownerDb.dispose);

    await SupabaseConfigRepository(ownerDb).setValues({key: 'owner wrote this'});

    final row = await live.client
        .from('config')
        .select('value')
        .eq('key', key)
        .single();
    expect(row['value'], 'admin wrote this',
        reason: 'staff is not the same permission as platform admin');
  });

  test('a change is recorded, so somebody can be asked about it later', () async {
    final key = ownKey('audited');
    await repository.setValues({key: 'a value'});

    // "Who raised the minimum version, and when" is a question asked only after
    // something has gone wrong, which is exactly when the answer has to already exist.
    final entries = await live.client
        .from('audit_log')
        .select('action, detail')
        .eq('action', 'config.set')
        .order('at', ascending: false)
        .limit(20);

    expect(
      entries.any((e) => (e['detail'] as Map).containsKey(key)),
      isTrue,
      reason: 'the change is in the log with the value it set',
    );
  });
}
