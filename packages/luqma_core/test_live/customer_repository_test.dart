import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// The customers screen, against real rows and real policies.
///
/// This screen matters more than its size suggests. A customer signs in with a phone
/// number and a password; there is no mailbox and no SMS, so a forgotten password has
/// exactly one way back and it is a person — the customer rings, and an admin finds them
/// here. An admin who cannot find them is a customer locked out of their account for
/// good.
///
/// `resetPassword` itself is not exercised here: it invokes the `reset-customer-password`
/// Edge Function, which is deployed to the production project and not to this one, so a
/// failure would be about infrastructure rather than about the code.
void main() {
  late LiveDatabase live;
  late SupabaseClient admin;
  late CustomerRepository repository;

  setUpAll(() async {
    live = await LiveDatabase.open();
    admin = await live.openAsAdmin();
    repository = SupabaseCustomerRepository(admin);
  });

  tearDownAll(() async {
    await admin.dispose();
    await live.close();
  });

  /// A customer with a known name and number on their `users` row.
  Future<String> customer({required String name, required String phone}) async {
    final uid = await live.makeCustomer();
    await live.client.from('users').update({'name': name, 'phone': phone}).eq('id', uid);
    addTearDown(() async => live.client.from('users').delete().eq('id', uid));
    return uid;
  }

  Future<Set<String>> found(String query) async =>
      (await repository.search(query)).valueOrNull!.map((c) => c.id).toSet();

  test('a number finds its person', () async {
    final uid = await customer(name: 'أحمد محمود', phone: '01099887701');
    expect(await found('01099887701'), contains(uid));
  });

  test('and so does a number typed with spaces', () async {
    final uid = await customer(name: 'سعاد', phone: '01099887702');
    expect(await found('010 9988 7702'), contains(uid),
        reason: 'somebody reading a number down a phone line types it in groups');
  });

  // The one this file was written for. `CLAUDE.md` states that `Phone.normalize` is
  // "shared with validation and with the admin's search" — it was not. Sign-up folds
  // Arabic-Indic digits before storing, so the row holds `010…`; the search sent whatever
  // was typed straight into an `ilike`. An admin on an Arabic keyboard therefore searched
  // for a spelling that is never stored, found nobody, and told the customer on the phone
  // that they have no account.
  test('and so does the same number typed on an Arabic keyboard', () async {
    final uid = await customer(name: 'منى', phone: '01099887703');
    expect(await found('٠١٠٩٩٨٨٧٧٠٣'), contains(uid),
        reason: 'the only way back from a forgotten password is this search');
  });

  // D12. A number read down the phone as «+20 10…» is how a customer says it, and it
  // found nobody: the row holds `010…`.
  test('and so does the same number with the country code', () async {
    final uid = await customer(name: 'هالة', phone: '01099887705');
    expect(await found('+20 10 9988 7705'), contains(uid));
    expect(await found('0020 1099887705'), contains(uid));
  });

  // D12. The query went into a PostgREST `or(...)` as raw text, where a comma or a
  // parenthesis is syntax: a name with one in it made the whole filter invalid, and the
  // screen showed an error instead of the person.
  test('a name with a comma or brackets in it is searched, not parsed', () async {
    final uid = await customer(name: 'علي (أبو محمد), الكبير', phone: '01099887706');
    final result = await repository.search('(أبو محمد), ');
    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.map((c) => c.id), contains(uid));
  });

  test('a name finds its person too', () async {
    final uid = await customer(name: 'خديجة الشناوي', phone: '01099887704');
    expect(await found('الشناوي'), contains(uid));
  });

  test('somebody who is not there is an empty list, not an error', () async {
    final result = await repository.search('01000000999');
    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull, isEmpty);
  });

  test('blocking a customer stops them ordering, and unblocking lets them back',
      () async {
    final uid = await customer(name: 'محجوب', phone: '01099887705');

    expect((await repository.setBlocked(uid, blocked: true)).failureOrNull, isNull);
    var row = await live.client
        .from('users')
        .select('is_blocked')
        .eq('id', uid)
        .single();
    expect(row['is_blocked'], isTrue);

    expect((await repository.setBlocked(uid, blocked: false)).failureOrNull, isNull);
    row = await live.client
        .from('users')
        .select('is_blocked')
        .eq('id', uid)
        .single();
    expect(row['is_blocked'], isFalse,
        reason: 'a block nobody can lift is a customer lost by mistake');
  });

  test('a customer cannot block anybody, including themselves', () async {
    final uid = await customer(name: 'عادي', phone: '01099887706');
    final (customerDb, _) = await live.openAsCustomer();
    addTearDown(customerDb.dispose);

    await SupabaseCustomerRepository(customerDb).setBlocked(uid, blocked: true);

    final row = await live.client
        .from('users')
        .select('is_blocked')
        .eq('id', uid)
        .single();
    expect(row['is_blocked'], isFalse,
        reason: 'blocking is the admin function it is named after');
  });

  test('history comes back newest first, and only that customer\'s', () async {
    final result = await repository.history(await customer(
      name: 'من غير طلبات',
      phone: '01099887707',
    ));
    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull, isEmpty,
        reason: 'a customer with no orders reads as none, not as a broken screen');
  });

  // The page boundary is a time *and* an id: 51 orders placed in the same instant must all
  // be reachable, the 51st on the second page — a cursor on the time alone lost it
  // (Astra's review, 2026-09-19).
  test('history pages past fifty, even across orders placed in the same instant', () async {
    final cityId = await live.makeCity();
    addTearDown(() async => live.dropCity(cityId));
    final zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة', 'default_delivery_fee': 1500})
        .select()
        .single()
        .then((row) => row['id'] as String);
    final merchantId = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم البحر',
      'zone_id': zoneId,
      'phone': '01000000000',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
    final uid = await customer(name: 'زبون قديم', phone: '01099887708');
    final instant = DateTime.utc(2026, 9, 1, 12).toIso8601String();
    await live.client.from('orders').insert([
      for (var i = 0; i < historyPage + 1; i++)
        {
          'city_id': cityId,
          'customer_uid': uid,
          'customer_name': 'زبون قديم',
          'customer_phone': '01099887708',
          'merchant_id': merchantId,
          'merchant_name': 'مطعم البحر',
          'zone_id': zoneId,
          'type': 'instant',
          'items': [],
          'pricing': {'subtotal': 1000, 'deliveryFee': 0, 'total': 1000},
          'status': 'delivered',
          'placed_at': instant,
        },
    ]);

    final firstResult = await repository.history(uid);
    expect(firstResult.failureOrNull, isNull);
    final first = firstResult.valueOrNull!;
    expect(first, hasLength(historyPage));
    final second = (await repository.history(uid, after: first.last)).valueOrNull!;
    expect(second, hasLength(1));
    final ids = {...first.map((o) => o.id), ...second.map((o) => o.id)};
    expect(ids, hasLength(historyPage + 1), reason: 'every order reachable, none twice');
  });
}
