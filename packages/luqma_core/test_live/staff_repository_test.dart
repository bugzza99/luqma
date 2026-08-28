import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// Who can see the staff list, asked through the repository the app actually uses.
///
/// The policy behind this has stack tests — it earned them, because it once read
/// `belongs_to_merchant`, which is true for an owner *and* their courier, so a rider
/// could read every account under the shop including the owner's phone number.
///
/// This file asks a different question, and it is the one that catches a whole class of
/// bug the stack tests cannot: `watchStaff` issues an unfiltered `select` and leans
/// entirely on the policy to narrow it. A rule that allows less than a query asks for
/// does not return less — Postgres returns the rows it can prove are readable, and a
/// query written against a rule that cannot prove it comes back empty or refused. Only
/// running the repository's own query answers that.
void main() {
  late LiveDatabase live;
  late String cityId, zoneId, merchantId;

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
    }).select().single().then((row) => row['id'] as String);
  });

  tearDown(() async {
    await live.client.from('staff').delete().eq('merchant_id', merchantId);
    await live.dropCity(cityId);
  });

  Future<List<StaffMember>> listedFor(SupabaseClient db) =>
      SupabaseStaffRepository(db).watchStaff().first;

  test('an admin sees the accounts, through the query the screen runs', () async {
    final (ownerDb, ownerUid) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(ownerDb.dispose);
    final admin = await live.openAsAdmin();
    addTearDown(admin.dispose);

    final listed = await listedFor(admin);

    expect(listed.map((s) => s.uid), contains(ownerUid),
        reason: 'AdminApp is the only screen that reads this list today');
  });

  test('a courier sees only their own row, not the shop they work for', () async {
    final (ownerDb, ownerUid) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(ownerDb.dispose);
    final (courierDb, courierUid) = await live.openAsStaff(
        scope: 'merchant', role: 'courier', merchantId: merchantId);
    addTearDown(courierDb.dispose);

    final listed = await listedFor(courierDb);

    // The finding this policy was rewritten for: an owner and their courier carry the
    // same `merchantId`, so a rule written on "belongs to this merchant" hands a rider
    // the owner's row — and the owner's phone number with it.
    expect(listed.map((s) => s.uid), [courierUid]);
    expect(listed.map((s) => s.uid), isNot(contains(ownerUid)));
  });

  test('an owner sees their own shop, and only their own shop', () async {
    final other = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم تاني',
      'zone_id': zoneId,
      'phone': '01000000001',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
    addTearDown(() async {
      await live.client.from('staff').delete().eq('merchant_id', other);
    });

    final (ownerDb, ownerUid) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(ownerDb.dispose);
    final (riderDb, riderUid) = await live.openAsStaff(
        scope: 'merchant', role: 'courier', merchantId: merchantId);
    addTearDown(riderDb.dispose);
    final (strangerDb, strangerUid) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: other);
    addTearDown(strangerDb.dispose);

    final listed = (await listedFor(ownerDb)).map((s) => s.uid).toSet();

    // The door left open on purpose for a merchant's own "my couriers" screen.
    expect(listed, containsAll([ownerUid, riderUid]));
    expect(listed, isNot(contains(strangerUid)),
        reason: 'another shop\'s people are not this owner\'s to read');
  });

  test('a customer sees nothing at all, and is not refused outright', () async {
    await live.openAsStaff(scope: 'merchant', role: 'owner', merchantId: merchantId);
    final (customer, _) = await live.openAsCustomer();
    addTearDown(customer.dispose);

    // Empty rather than an error: a customer has no staff row, so the policy proves
    // nothing readable and the query is answerable — which is what the app needs, since
    // a thrown query would surface as a broken screen rather than an empty one.
    expect(await listedFor(customer), isEmpty);
  });

  test('the list puts the disabled accounts last', () async {
    final (activeDb, activeUid) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(activeDb.dispose);
    final (goneDb, goneUid) = await live.openAsStaff(
        scope: 'merchant', role: 'courier', merchantId: merchantId);
    addTearDown(goneDb.dispose);

    final admin = await live.openAsAdmin();
    addTearDown(admin.dispose);
    final repository = SupabaseStaffRepository(admin);

    expect((await repository.setActive(goneUid, active: false)).failureOrNull, isNull);

    final listed = (await repository.watchStaff().first)
        .where((s) => s.uid == activeUid || s.uid == goneUid)
        .toList();

    expect(listed.first.uid, activeUid);
    expect(listed.last.uid, goneUid);
    expect(listed.last.isActive, isFalse);
  });

  test('only an admin may switch an account off', () async {
    final (ownerDb, ownerUid) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(ownerDb.dispose);
    final (courierDb, courierUid) = await live.openAsStaff(
        scope: 'merchant', role: 'courier', merchantId: merchantId);
    addTearDown(courierDb.dispose);

    // An owner can *read* their courier. Writing is the admin's alone — an owner who can
    // disable accounts can disable the admin's.
    await SupabaseStaffRepository(ownerDb)
        .setActive(courierUid, active: false);

    final row = await live.client
        .from('staff')
        .select('is_active')
        .eq('uid', courierUid)
        .single();
    expect(row['is_active'], isTrue,
        reason: 'the write was refused, whatever the call reported');

    // And a courier cannot switch the owner off either.
    await SupabaseStaffRepository(courierDb).setActive(ownerUid, active: false);
    final owner = await live.client
        .from('staff')
        .select('is_active')
        .eq('uid', ownerUid)
        .single();
    expect(owner['is_active'], isTrue);
  });
}
