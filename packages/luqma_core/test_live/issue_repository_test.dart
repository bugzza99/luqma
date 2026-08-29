import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// Complaints, and who may close them.
///
/// A ticket is what a customer opens when an order went wrong, and closing one is the
/// admin saying it has been dealt with. If a customer could close their own, the queue
/// would empty itself of exactly the complaints somebody wanted to escalate.
void main() {
  late LiveDatabase live;
  late String cityId, zoneId, merchantId;
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
        .insert({'city_id': cityId, 'name': 'منطقة', 'default_delivery_fee': 1500})
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
    await live.client.from('order_issues').delete().eq('merchant_id', merchantId);
    await live.dropCity(cityId);
  });

  /// One complaint, on a delivered order, from [uid].
  Future<String> issue(String uid) async {
    final orderId = await live.client.from('orders').insert({
      'city_id': cityId,
      'customer_uid': uid,
      'customer_name': 'عميل',
      'customer_phone': '01000000000',
      'merchant_id': merchantId,
      'merchant_name': 'مطعم البحر',
      'zone_id': zoneId,
      'type': 'instant',
      'items': [],
      'pricing': {'total': 10000},
      'status': 'delivered',
    }).select().single().then((row) => row['id'] as String);

    return live.client.from('order_issues').insert({
      'order_id': orderId,
      'merchant_id': merchantId,
      'customer_uid': uid,
      'reason': 'الأكل وصل بارد',
      'status': OrderIssue.open,
    }).select().single().then((row) => row['id'] as String);
  }

  Future<String> statusOf(String id) async => (await live.client
      .from('order_issues')
      .select('status')
      .eq('id', id)
      .single())['status'] as String;

  test('an admin sees an open complaint in the queue', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final id = await issue(uid);

    final listed = await SupabaseIssueRepository(admin).watchIssues().first;

    expect(listed.map((i) => i.id), contains(id));
  });

  test('an admin closes it, with the note they were told to leave', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final id = await issue(uid);

    final result = await SupabaseIssueRepository(admin)
        .close(id, adminNote: 'اتكلمنا مع المطعم واترد الفرق');

    expect(result.failureOrNull, isNull);
    expect(await statusOf(id), OrderIssue.closed);

    final row = await live.client
        .from('order_issues')
        .select('admin_note')
        .eq('id', id)
        .single();
    // The note is what the next person to read this ticket has instead of a memory of
    // the phone call.
    expect(row['admin_note'], 'اتكلمنا مع المطعم واترد الفرق');
  });

  test('closing with no note leaves the ticket closed and unannotated', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final id = await issue(uid);

    await SupabaseIssueRepository(admin).close(id);

    expect(await statusOf(id), OrderIssue.closed);
  });

  test('a customer cannot close their own complaint', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final id = await issue(uid);

    await SupabaseIssueRepository(customer).close(id, adminNote: 'خلاص مفيش مشكلة');

    expect(await statusOf(id), OrderIssue.open,
        reason: 'the queue would empty itself of the complaints somebody escalated');
  });

  test('a merchant cannot close a complaint made against them', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final id = await issue(uid);

    final (ownerDb, _) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(ownerDb.dispose);

    await SupabaseIssueRepository(ownerDb).close(id, adminNote: 'مفيش حاجة');

    // The shop being complained about is the last party who should be able to mark the
    // complaint dealt with.
    expect(await statusOf(id), OrderIssue.open);
  });

  test('open complaints sort ahead of closed ones', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);
    final closed = await issue(uid);
    final open = await issue(uid);
    await SupabaseIssueRepository(admin).close(closed);

    final listed = (await SupabaseIssueRepository(admin).watchIssues().first)
        .where((i) => i.id == open || i.id == closed)
        .toList();

    expect(listed.first.id, open,
        reason: 'what still needs answering is what the screen is for');
    expect(listed.last.id, closed);
  });
}
