import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// Joining, end to end, through real tokens: an applicant makes their phone account,
/// applies, and an admin's approval turns the application into an account.
///
/// This is the path the first real merchant took on 2026-09-18 — he applied, was
/// approved, and vanished, because approval wrote `approved` on a row and created
/// nothing. `20261005000000` rebuilt it, the fakes and the stack tests cover pieces of it,
/// and until this file nothing had walked it through the repository the app actually
/// calls, with the token the app actually holds, against the policies production runs.
void main() {
  late LiveDatabase live;
  late SupabaseClient adminDb;
  late SupabaseStaffApplicationRepository admin;
  late String cityId;
  late String zoneId;

  setUpAll(() async {
    live = await LiveDatabase.open();
    adminDb = await live.openAsAdmin();
    admin = SupabaseStaffApplicationRepository(adminDb);
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة'})
        .select()
        .single()
        .then((row) => row['id'] as String);
  });

  tearDown(() async {
    // What approval made: the staff rows point at the shop, and the shop is the city's.
    final shops = await live.client.from('merchants').select('id').eq('city_id', cityId);
    final ids = shops.map((m) => m['id'] as String).toList();
    if (ids.isNotEmpty) {
      await live.client.from('staff').delete().inFilter('merchant_id', ids);
    }
    await live.dropCity(cityId);
  });

  tearDownAll(() async {
    await adminDb.dispose();
    await live.close();
  });

  /// A number no other run has used. The accounts are committed; the cloud cleanup
  /// removes them between runs.
  String freshNumber() =>
      '011${DateTime.now().microsecondsSinceEpoch % 100000000}'.padRight(11, '0')
          .substring(0, 11);

  /// Signs up the way MerchantApp's apply form does: an ordinary phone account first.
  Future<(SupabaseClient, String, String)> applicantAccount() async {
    final client = live.openAnonymously();
    final phone = freshNumber();
    final identity = (await SupabaseAuthService(client).signUpWithPhone(
      phone: phone,
      password: 'luqma1234',
      name: 'مطعم الاختبار',
    )).valueOrNull!;
    return (client, identity.uid, phone);
  }

  Future<StaffApplication> pendingFor(String phone) async {
    final pending = await admin.watchPending().first;
    return pending.singleWhere((a) => a.phone == phone);
  }

  test('a restaurant that applies and is approved becomes an owner with a shop',
      () async {
    final (applicantDb, uid, phone) = await applicantAccount();
    addTearDown(applicantDb.dispose);

    final applied = await SupabaseStaffApplicationRepository(applicantDb).apply(
      kind: StaffApplicationKind.restaurant,
      name: 'مطعم الاختبار',
      phone: phone,
      applicantUid: uid,
    );
    expect(applied.failureOrNull, isNull, reason: 'the applicant can file it');

    final application = await pendingFor(phone);
    final approved = await admin.approve(application.id, zoneId: zoneId);
    expect(approved.failureOrNull, isNull);

    // What the incident lacked, all three: the account became staff, bound to a shop
    // that exists, in the zone the admin picked, waiting for its details.
    final staff = await live.client.from('staff').select().eq('uid', uid).single();
    expect(staff['role'], 'owner');
    expect(staff['merchant_id'], isNotNull);
    final shop = await live.client
        .from('merchants')
        .select()
        .eq('id', staff['merchant_id'] as String)
        .single();
    expect(shop['zone_id'], zoneId);
    expect(shop['city_id'], cityId);
    expect(shop['status'], 'pending');

    // And the queue no longer lists it.
    final stillPending = await admin.watchPending().first;
    expect(stillPending.where((a) => a.phone == phone), isEmpty);
  });

  // The theft the signed application closes: file a real restaurant's name and number
  // against your own account, let the owner ring the restaurant and agree terms, and
  // approval hands you the shop.
  test('nobody can apply under a number their account does not hold', () async {
    final (applicantDb, uid, _) = await applicantAccount();
    addTearDown(applicantDb.dispose);

    final result = await SupabaseStaffApplicationRepository(applicantDb).apply(
      kind: StaffApplicationKind.restaurant,
      name: 'مطعم غيري',
      phone: freshNumber(),
      applicantUid: uid,
    );

    expect(result.failureOrNull, isNotNull);
  });

  test('an application needs an account behind it', () async {
    final anonymous = live.openAnonymously();
    addTearDown(anonymous.dispose);

    final result = await SupabaseStaffApplicationRepository(anonymous).apply(
      kind: StaffApplicationKind.courier,
      name: 'مندوب',
      phone: freshNumber(),
    );

    expect(result.failureOrNull, isNotNull);
  });

  test('a second open application for the same number is refused by name', () async {
    final (applicantDb, uid, phone) = await applicantAccount();
    addTearDown(applicantDb.dispose);
    final repository = SupabaseStaffApplicationRepository(applicantDb);

    await repository.apply(
      kind: StaffApplicationKind.restaurant,
      name: 'مطعم الاختبار',
      phone: phone,
      applicantUid: uid,
    );
    final again = await repository.apply(
      kind: StaffApplicationKind.restaurant,
      name: 'مطعم الاختبار',
      phone: phone,
      applicantUid: uid,
    );

    expect(again.failureOrNull, isA<AlreadyAppliedFailure>());
  });

  // The incident, reproduced by an older admin APK: a review that said `approved` and
  // created nothing. The server refuses it now, whatever build asks.
  test('approving through review is refused, so nothing is approved into nothing',
      () async {
    final (applicantDb, uid, phone) = await applicantAccount();
    addTearDown(applicantDb.dispose);
    await SupabaseStaffApplicationRepository(applicantDb).apply(
      kind: StaffApplicationKind.restaurant,
      name: 'مطعم الاختبار',
      phone: phone,
      applicantUid: uid,
    );
    final application = await pendingFor(phone);

    final result = await admin.review(
      application.id,
      status: StaffApplicationStatus.approved,
    );

    expect(result.failureOrNull, isNotNull);
    final staff = await live.client.from('staff').select().eq('uid', uid);
    expect(staff, isEmpty);
  });

  test('a shop cannot be approved without a zone, and says so as a validation',
      () async {
    final (applicantDb, uid, phone) = await applicantAccount();
    addTearDown(applicantDb.dispose);
    await SupabaseStaffApplicationRepository(applicantDb).apply(
      kind: StaffApplicationKind.homeKitchen,
      name: 'مطبخ الاختبار',
      phone: phone,
      applicantUid: uid,
    );
    final application = await pendingFor(phone);

    final result = await admin.approve(application.id);

    expect(result.failureOrNull, isA<ValidationFailure>(),
        reason: '«a shop needs a zone» is 22023, a validation — the fake says the same');
  });
}
