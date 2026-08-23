import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:luqma_core/luqma_core.dart';

/// Asks Google for a credential, or returns null when the person backed out.
///
/// Null is not an error. Somebody who opens the Google sheet and changes their mind has
/// made a decision, and an app that answers it with a red banner is apologising for
/// their choice.
///
/// This is the only file in the project that knows Google exists. Everything above it
/// talks to `AuthService`, which is why the entire account flow — signing in, signing
/// out, addresses following the session, checkout asking for an account — is tested
/// without a device, an OAuth client, or a network.
///
/// It needs three things that are not code, all in the Firebase console: Google enabled
/// as a sign-in provider, the signing key's SHA-1 registered against `com.luqma.customer`,
/// and the resulting **web** client id in [LuqmaFirebase.googleServerClientId]. Until
/// then this throws with those instructions. See the Phase 3 note in CLAUDE.md.
Future<AuthCredential?> googleCredential() async {
  if (LuqmaFirebase.googleServerClientId.isEmpty) {
    // Said plainly and early, because the failure it replaces — "serverClientId must be
    // provided on Android" — names a field nobody set rather than the step nobody did.
    throw StateError(
      'Google Sign-In is not configured yet. In the Firebase console: enable Google '
      'under Authentication → Sign-in method, add the signing key SHA-1 to the '
      'com.luqma.customer app under Project settings, then put the Web client id in '
      'LuqmaFirebase.googleServerClientId.',
    );
  }

  final google = GoogleSignIn.instance;
  // Android has no google-services.json here, so the web client id cannot be read from
  // resources and has to be handed over.
  await google.initialize(serverClientId: LuqmaFirebase.googleServerClientId);

  final account = await google.authenticate();
  final auth = account.authentication;
  final idToken = auth.idToken;
  if (idToken == null) return null;

  return GoogleAuthProvider.credential(idToken: idToken);
}
