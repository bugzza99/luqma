import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'harness.dart';

void main() {
  late LiveDatabase live;
  late String cityId;
  late String zoneId;
  late String merchantId1;
  late String merchantId2;
  late SupabaseClient owner1;
  late SupabaseClient admin;

  setUpAll(() async {
    live = await LiveDatabase.open();
    admin = await live.openAsAdmin();
  });

  tearDownAll(() async {
    await admin.dispose();
    await live.close();
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة'})
        .select()
        .single()
        .then((row) => row['id'] as String);

    merchantId1 = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم 1',
      'zone_id': zoneId,
      'phone': '01000000001',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);

    merchantId2 = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم 2',
      'zone_id': zoneId,
      'phone': '01000000002',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);

    final (client, _) = await live.openAsStaff(
      scope: 'merchant',
      role: 'owner',
      merchantId: merchantId1,
    );
    owner1 = client;
  });

  tearDown(() async {
    await owner1.dispose();
    await live.dropCity(cityId);
  });

  Coupon draft({
    String code = 'SAVE20',
    String? merchantId,
    CouponType type = CouponType.percentage,
    int value = 20,
    int? maxDiscount = 5000,
    CouponFunder fundedBy = CouponFunder.merchant,
  }) {
    return Coupon(
      id: '',
      code: code,
      cityId: cityId,
      type: type,
      value: value,
      maxDiscount: maxDiscount,
      merchantId: merchantId ?? merchantId1,
      fundedBy: fundedBy,
      validFrom: DateTime.now().subtract(const Duration(days: 1)),
      validUntil: DateTime.now().add(const Duration(days: 30)),
      isActive: true,
      createdByUid: '',
    );
  }

  test('owner creates, lists, and pauses own coupon', () async {
    final repo = SupabaseCouponRepository(owner1);

    // 1. Create
    final createdResult = await repo.create(draft(code: 'SAVE20'));
    expect(createdResult.isOk, isTrue);
    final created = createdResult.valueOrNull!;
    expect(created.code, 'SAVE20');
    expect(created.id, isNotEmpty);
    expect(created.isActive, isTrue);

    // 2. Watch/list for own merchant
    final coupons = await repo.watchForMerchant(merchantId1).first;
    expect(coupons.any((c) => c.id == created.id), isTrue);

    // 3. Pause (setActive = false)
    final pauseResult = await repo.setActive(created.id, false);
    expect(pauseResult.isOk, isTrue);

    final updated = await repo.watchForMerchant(merchantId1).first;
    final paused = updated.firstWhere((c) => c.id == created.id);
    expect(paused.isActive, isFalse);
  });

  test('owner cannot write coupon for another shop', () async {
    final repo = SupabaseCouponRepository(owner1);

    // Attempt to create coupon for merchantId2
    final result = await repo.create(draft(code: 'OTHER10', merchantId: merchantId2));
    expect(result.failureOrNull, isNotNull);
  });

  test('admin lists all coupons across merchants', () async {
    final ownerRepo = SupabaseCouponRepository(owner1);
    await ownerRepo.create(draft(code: 'SHOP10'));

    final adminRepo = SupabaseCouponRepository(admin);
    final listResult = await adminRepo.listAll();
    expect(listResult.isOk, isTrue);
    final all = listResult.valueOrNull!;
    expect(all.any((c) => c.code == 'SHOP10'), isTrue);
  });
}
