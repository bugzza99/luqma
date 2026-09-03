import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Nothing in `LuqmaPush` may touch Firebase before Firebase exists.
///
/// This is the whole file's reason: `main` wires push up in its first few lines, and
/// `Firebase.initializeApp()` is deliberately *not* awaited there — it asks for the
/// notification permission, and awaiting a system dialog before `runApp` holds the first
/// frame on a white screen until somebody answers it.
///
/// So every entry point here is reached while Firebase may not be ready, and any one that
/// reads `FirebaseMessaging.instance` eagerly throws `[core/no-app]` — uncaught, inside
/// `main`, which is not a degraded feature but an app that does not start. That shipped:
/// `tokenRefreshes` was written as an expression-bodied getter over
/// `FirebaseMessaging.instance.onTokenRefresh`, and three release APKs died on launch.
///
/// A `flutter test` process has no Firebase at all, which is exactly the condition being
/// asserted — so these are cheap, and they are the only tests that can see this class of
/// fault before a phone does.
void main() {
  // Starting reaches for a platform channel, which needs a binding. Without this the
  // failure is caught and the test still passes, but it passes over a page of unrelated
  // noise — and a suite whose output is never clean is a suite nobody reads.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asking for the refresh stream does not need Firebase yet', () {
    expect(() => LuqmaPush.tokenRefreshes, returnsNormally);
  });

  // Reading the getter is not enough on its own: an expression-bodied getter evaluates
  // its body on the *read*, and a lazy one evaluates on the *listen*. Both have to be
  // safe, because `keepPushTokenRegistered` subscribes the moment it is called.
  test('and neither does listening to it', () async {
    final subscription = LuqmaPush.tokenRefreshes.listen((_) {});
    addTearDown(subscription.cancel);

    // A turn of the loop, so an `async*` body that throws on its first await lands here
    // rather than after the test has finished.
    await Future<void>.delayed(Duration.zero);
  });

  test('asking for a token answers null rather than throwing', () async {
    expect(await LuqmaPush.token(), isNull);
  });

  /// A build with no `google-services.json` is a normal state — a developer's machine, a
  /// fresh clone, CI — and it must leave an app that runs rather than one that crashes.
  test('starting without Firebase configured says so instead of throwing', () async {
    expect(await LuqmaPush.start(), isFalse);
  });
}
