import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// Signing up and signing in with a phone number, against real GoTrue.
///
/// The whole customer account rests on one thing that cannot be checked against a fake:
/// that GoTrue accepts this at all. It does *not* accept its own phone identity here —
/// that needs an SMS provider, and the CLI refuses to enable it without one — so the
/// number is folded into a synthetic address and GoTrue holds an ordinary email
/// identity. Whether that fold works end to end is this file's only question.
///
/// It is asked through `SupabaseAuthService` rather than the SDK, for the reason the
/// claims bug taught: every layer was verified on its own and the seam between them was
/// where the product was broken.
void main() {
  late LiveDatabase live;

  setUpAll(() async {
    live = await LiveDatabase.open();
  });

  tearDownAll(() => live.close());

  /// A number no other run has used. These accounts are committed, not rolled back.
  String freshNumber() =>
      '010${DateTime.now().microsecondsSinceEpoch % 100000000}'.padRight(11, '0')
          .substring(0, 11);

  test('somebody with a phone and a password becomes an account', () async {
    final client = live.openAnonymously();
    addTearDown(client.dispose);
    final auth = SupabaseAuthService(client);
    final phone = freshNumber();

    // Watched the way the app watches it — `currentIdentityProvider` is a listener on
    // this stream, not a reader of `state`, and the listener is what a screen redraws on.
    final signedIn = auth.changes.firstWhere((i) => i != null);

    final result = await auth.signUpWithPhone(
      phone: phone,
      password: 'luqma1234',
      name: 'أحمد محمود',
    );

    expect(result.failureOrNull, isNull, reason: 'real GoTrue accepted it');
    expect(
      await signedIn.timeout(const Duration(seconds: 5)),
      isNotNull,
      reason: 'everybody watching the session learns about it',
    );
    expect(result.valueOrNull?.phone, phone,
        reason: 'the number they typed, not the address it was folded into');
    expect(result.valueOrNull?.email, isNull,
        reason: 'the synthetic address is never shown to anybody');
  });

  // What `place_order` copies onto an order, and what the courier calls. The trigger is
  // the only thing that puts it there.
  test('their number reaches the users row the courier reads', () async {
    final client = live.openAnonymously();
    addTearDown(client.dispose);
    final auth = SupabaseAuthService(client);
    final phone = freshNumber();

    final identity = (await auth.signUpWithPhone(
      phone: phone,
      password: 'luqma1234',
      name: 'سارة',
    )).valueOrNull!;

    final row = await live.client
        .from('users')
        .select('name, phone')
        .eq('id', identity.uid)
        .single();

    expect(row['phone'], phone);
    expect(row['name'], 'سارة');
  });

  test('they can come back with the same number and password', () async {
    final phone = freshNumber();
    final first = live.openAnonymously();
    addTearDown(first.dispose);
    final signedUp = (await SupabaseAuthService(first).signUpWithPhone(
      phone: phone,
      password: 'luqma1234',
      name: 'أحمد',
    )).valueOrNull!;

    // A second client, the way a second phone — or the same phone after a sign-out —
    // arrives: with nothing but what the person can type.
    final second = live.openAnonymously();
    addTearDown(second.dispose);
    final auth = SupabaseAuthService(second);

    final result =
        await auth.signInWithPhone(phone: phone, password: 'luqma1234');

    expect(result.valueOrNull?.uid, signedUp.uid,
        reason: 'the same account, not a second one');
  });

  // However they spell it. An Arabic keyboard produces ٠١٠… and the account was made
  // with 010…; two spellings reaching two accounts is one person losing their history.
  test('the same number typed in Arabic digits is the same account', () async {
    final phone = freshNumber();
    final first = live.openAnonymously();
    addTearDown(first.dispose);
    final signedUp = (await SupabaseAuthService(first).signUpWithPhone(
      phone: phone,
      password: 'luqma1234',
      name: 'أحمد',
    )).valueOrNull!;

    const western = '0123456789';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final asArabic = phone.split('').map((d) => arabic[western.indexOf(d)]).join();

    final second = live.openAnonymously();
    addTearDown(second.dispose);
    final result = await SupabaseAuthService(second)
        .signInWithPhone(phone: asArabic, password: 'luqma1234');

    expect(result.valueOrNull?.uid, signedUp.uid);
  });

  test('a wrong password is refused', () async {
    final phone = freshNumber();
    final first = live.openAnonymously();
    addTearDown(first.dispose);
    await SupabaseAuthService(first)
        .signUpWithPhone(phone: phone, password: 'luqma1234', name: 'أحمد');

    final second = live.openAnonymously();
    addTearDown(second.dispose);
    final result = await SupabaseAuthService(second)
        .signInWithPhone(phone: phone, password: 'not-the-password');

    expect(result.failureOrNull, isNotNull);
    expect(result.valueOrNull, isNull);
  });

  // The number is the identity, so a second account on it is somebody who already has
  // orders under that number — and who should be signing in.
  test('a number that already has an account cannot make a second', () async {
    final phone = freshNumber();
    final first = live.openAnonymously();
    addTearDown(first.dispose);
    await SupabaseAuthService(first)
        .signUpWithPhone(phone: phone, password: 'luqma1234', name: 'أحمد');

    final second = live.openAnonymously();
    addTearDown(second.dispose);
    final result = await SupabaseAuthService(second).signUpWithPhone(
      phone: phone,
      password: 'a-different-one',
      name: 'شخص تاني',
    );

    expect(result.failureOrNull, isA<PhoneTakenFailure>(),
        reason: 'and the screen tells them to sign in instead');
  });
}
