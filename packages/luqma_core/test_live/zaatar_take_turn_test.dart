import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'harness.dart';

/// «زعتر»'s turn counter, through a real token.
///
/// `zaatar_usage` is `force row level security` with **no policies at all**, and every
/// grant on it is revoked. So the insert inside `zaatar_take_turn` works only because a
/// `security definer` function's owner bypasses forced RLS — a claim PGlite cannot test,
/// since it runs as a superuser and would pass either way.
///
/// The failure mode is the reason this file exists rather than a note: if the definer did
/// not bypass, the function would raise, the Edge Function folds any error into the
/// local rule-based answer, and every suite would stay green while «زعتر» silently never
/// reached the model again. Same shape as `app_opens`, tested the same way.
void main() {
  late LiveDatabase live;

  setUpAll(() async {
    live = await LiveDatabase.open();
  });

  tearDownAll(() => live.close());

  test('a signed-in customer may take a turn, and the count rises', () async {
    final (customerDb, uid) = await live.openAsCustomer();
    addTearDown(customerDb.dispose);
    addTearDown(() => live.client.from('zaatar_usage').delete().eq('uid', uid));

    final first = await customerDb.rpc<bool>('zaatar_take_turn');
    expect(first, isTrue, reason: 'the first turn of the day is always allowed');

    final second = await customerDb.rpc<bool>('zaatar_take_turn');
    expect(second, isTrue);

    // Read back through the service key, because the customer may not read it herself —
    // see below. The count is what the cap is judged against, so a function that returned
    // true without writing would be indistinguishable here from one that worked.
    final rows = await live.client
        .from('zaatar_usage')
        .select('count')
        .eq('uid', uid) as List;
    expect(rows, hasLength(1));
    expect(rows.single['count'], 2,
        reason: 'the second turn incremented the row rather than making another');
  });

  test('and the counter is not the customer to read or to write', () async {
    final (customerDb, uid) = await live.openAsCustomer();
    addTearDown(customerDb.dispose);
    addTearDown(() => live.client.from('zaatar_usage').delete().eq('uid', uid));

    await customerDb.rpc<bool>('zaatar_take_turn');

    // Every grant is revoked, so this is a refusal rather than an empty list — and the
    // difference matters: a table filtered to nothing by a policy still lets a client
    // learn the shape of it, and a counter a customer can write is a cap they can lift.
    await expectLater(
      customerDb.from('zaatar_usage').select(),
      throwsA(isA<PostgrestException>()),
    );
    await expectLater(
      customerDb.from('zaatar_usage').update({'count': 0}).eq('uid', uid),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('and an account that is not signed in cannot take one at all', () async {
    final anon = live.openAnonymously();
    addTearDown(anon.dispose);

    // `execute` is granted to `authenticated` and to nobody else. Not a cosmetic
    // boundary: the cap is per `auth.uid()`, and a caller with no uid has no cap.
    await expectLater(
      anon.rpc<bool>('zaatar_take_turn'),
      throwsA(isA<PostgrestException>()),
    );
  });
}
