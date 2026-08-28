import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// The number a customer types at checkout, and what the courier ends up dialling.
///
/// `users.phone` is not a display field. `place_order` copies it onto the order, and the
/// order is what the courier reads in the street — so this is the last place a phone
/// number can go wrong before somebody is standing at a door unable to ring.
void main() {
  late LiveDatabase live;

  setUpAll(() async => live = await LiveDatabase.open());
  tearDownAll(() => live.close());

  Future<String?> phoneOf(String uid) async => (await live.client
      .from('users')
      .select('phone')
      .eq('id', uid)
      .single())['phone'] as String?;

  test('a customer saves their own number', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);

    final result = await SupabaseProfileRepository(customer)
        .savePhone(uid: uid, phone: '01099887711');

    expect(result.failureOrNull, isNull);
    expect(await phoneOf(uid), '01099887711');
  });

  // The one this file was written for. `Phone.isValidEgyptianMobile` folds Arabic-Indic
  // digits *inside itself* before matching, so checkout's validation passes on `٠١٠…`
  // and then hands the raw text straight to this repository.
  //
  // Sign-up stores `010…`, so the account and the profile end up holding two spellings
  // of one number: the admin's search finds nobody, and the number stamped on the order
  // is whichever the customer last typed.
  test('a number typed on an Arabic keyboard is stored the way every other is',
      () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);

    await SupabaseProfileRepository(customer)
        .savePhone(uid: uid, phone: '٠١٠٩٩٨٨٧٧١٢');

    expect(await phoneOf(uid), '01099887712',
        reason: 'one number, one spelling — that is what the whole account rests on');
  });

  test('spaces and dashes are not part of the number', () async {
    final (customer, uid) = await live.openAsCustomer();
    addTearDown(customer.dispose);

    await SupabaseProfileRepository(customer)
        .savePhone(uid: uid, phone: '010 9988-7713');

    expect(await phoneOf(uid), '01099887713');
  });

  test('a customer cannot write somebody else\'s number onto their row', () async {
    final (mine, myUid) = await live.openAsCustomer();
    addTearDown(mine.dispose);
    final (theirs, theirUid) = await live.openAsCustomer();
    addTearDown(theirs.dispose);

    await SupabaseProfileRepository(mine)
        .savePhone(uid: myUid, phone: '01099887714');
    // The uid is a parameter, so nothing in the call itself stops this — only the policy
    // does, and a courier ringing the wrong person is the cheapest possible way to leak
    // where somebody lives.
    await SupabaseProfileRepository(mine)
        .savePhone(uid: theirUid, phone: '01000000000');

    expect(await phoneOf(theirUid), isNot('01000000000'));
  });
}
