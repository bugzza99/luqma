import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// What customers said, as the merchant reads it, against a real Postgres.
///
/// A rating is keyed by its order here rather than by a document id, so seeding one
/// means placing a real order first — which is exactly the discipline the primary key
/// asks of production.
void main() {
  late LiveDatabase live;
  late SupabaseFeedbackRepository repository;
  late String cityId;
  late String zoneId;
  late String merchantId;
  late String customerUid;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseFeedbackRepository(live.client);
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة'})
        .select()
        .single()
        .then((row) => row['id'] as String);
    merchantId = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم',
      'zone_id': zoneId,
      'phone': '01000000000',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
    customerUid = await live.makeCustomer();
  });

  tearDown(() => live.dropCity(cityId));
  tearDownAll(() => live.close());

  Future<String> placeOrder() async => await live.client.from('orders').insert({
    'city_id': cityId,
    'customer_uid': customerUid,
    'customer_name': 'عميل',
    'customer_phone': '0100',
    'merchant_id': merchantId,
    'merchant_name': 'مطعم',
    'zone_id': zoneId,
    'type': 'instant',
    'items': <dynamic>[],
    'pricing': <String, dynamic>{'total': 0},
    'address': {'zoneId': zoneId},
  }).select().single().then((row) => row['id'] as String);

  Future<void> rate(
    String orderId, {
    int stars = 5,
    String? comment,
    DateTime? at,
  }) async =>
      await live.client.from('ratings').insert({
        'order_id': orderId,
        'merchant_id': merchantId,
        'customer_uid': customerUid,
        'stars': stars,
        'comment': comment,
        if (at != null) 'created_at': at.toUtc().toIso8601String(),
      });

  test("only this merchant's", () async {
    final mine = await placeOrder();
    await rate(mine, comment: 'ممتاز');

    final otherMerchant = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم تاني',
      'zone_id': zoneId,
      'phone': '01000000001',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
    final theirsOrder = await live.client.from('orders').insert({
      'city_id': cityId,
      'customer_uid': customerUid,
      'customer_name': 'عميل',
      'customer_phone': '0100',
      'merchant_id': otherMerchant,
      'merchant_name': 'مطعم تاني',
      'zone_id': zoneId,
      'type': 'instant',
      'items': <dynamic>[],
      'pricing': <String, dynamic>{'total': 0},
      'address': {'zoneId': zoneId},
    }).select().single().then((row) => row['id'] as String);
    await live.client.from('ratings').insert({
      'order_id': theirsOrder,
      'merchant_id': otherMerchant,
      'customer_uid': customerUid,
      'stars': 1,
      'comment': 'وحش',
    });

    final feedback = await repository.watchFeedback(merchantId).first;

    expect(feedback.map((f) => f.orderId), [mine]);
  });

  test('the stars and the words both come through', () async {
    final order = await placeOrder();
    await rate(order, stars: 2, comment: 'الأكل وصل بارد');

    final one = (await repository.watchFeedback(merchantId).first).single;

    expect(one.stars, 2);
    expect(one.comment, 'الأكل وصل بارد');
  });

  // Most people rate without typing. Dropping those would make the list look like
  // nothing but complaints, because complaints are what people write.
  test('a rating with no comment is still feedback', () async {
    final order = await placeOrder();
    await rate(order);

    final one = (await repository.watchFeedback(merchantId).first).single;

    expect(one.stars, 5);
    expect(one.comment, isNull);
  });
}
