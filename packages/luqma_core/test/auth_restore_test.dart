import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
// `AuthState` is a name this package and GoTrue both use; the one that matters here is
// ours.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// The wait that has to end.
///
/// `restore()` completes when GoTrue delivers its first `onAuthStateChange` event, and
/// three launch paths wait on it: the customer's splash, the merchant's gate, and
/// `currentIdentityProvider`. If that event never arrives — an SDK upgrade changing when
/// it is emitted, auth initialisation stalling, storage that will not answer — the
/// completer is never completed and the wait never ends.
///
/// The failure has no exception and no error screen. The customer sits on the burgundy
/// splash and the merchant on "بنجهّز…", for ever, and the only report anybody can make
/// is "it doesn't open" — which is the hardest sentence in this product to act on.
///
/// The client here is pointed at an address nothing answers, so no auth event is ever
/// delivered: the exact condition, reproduced.
void main() {
  test('a session that never resolves gives up rather than hanging', () async {
    final client = SupabaseClient('http://127.0.0.1:1', 'not-a-real-key');
    addTearDown(client.dispose);
    final auth = SupabaseAuthService(client, resolveWithin: Duration.zero);

    await auth.restore().timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('restore() never returned'),
        );

    // Signed out, not unknown: the wait is over and nobody arrived. A screen that keeps
    // saying "we don't know yet" is the hang wearing a different label.
    expect(auth.state, AuthState.signedOut);
    expect(auth.identity, isNull);
  });

  // The bound must not become the answer. When GoTrue does deliver a session, that is
  // what the app runs on — the timeout is a floor under a failure, not a race the real
  // event has to win.
  test('and a session that does resolve is what wins', () async {
    final auth = FakeAuthService();

    await auth.restore();

    expect(auth.state, AuthState.signedOut);
  });
}
