import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
/// It needs one thing that is not code: the app's SHA-1 fingerprint registered against
/// `com.luqma.customer` in the Firebase console, with Google enabled as a sign-in
/// provider. Until that is done this returns an error at run time on a real phone. See
/// the Phase 3 note in CLAUDE.md.
Future<AuthCredential?> googleCredential() async {
  final google = GoogleSignIn.instance;
  await google.initialize();

  final account = await google.authenticate();
  final auth = account.authentication;
  final idToken = auth.idToken;
  if (idToken == null) return null;

  return GoogleAuthProvider.credential(idToken: idToken);
}
