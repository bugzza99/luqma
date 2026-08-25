import 'package:google_sign_in/google_sign_in.dart';

/// Asks Google for an id token, or returns null when the person backed out.
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
/// It needs two things that are not code: Google configured as a sign-in provider in the
/// Supabase dashboard, and the **web** client id handed to the build as
/// `LUQMA_GOOGLE_WEB_CLIENT_ID`. Until then this throws with those instructions.
Future<String?> googleIdToken() async {
  const serverClientId = String.fromEnvironment('LUQMA_GOOGLE_WEB_CLIENT_ID');
  if (serverClientId.isEmpty) {
    // Said plainly and early, because the failure it replaces — "serverClientId must be
    // provided on Android" — names a field nobody set rather than the step nobody did.
    throw StateError(
      'Google Sign-In is not configured yet. In the Supabase dashboard: enable Google '
      'under Authentication → Providers and add the OAuth credentials; then build with '
      '--dart-define=LUQMA_GOOGLE_WEB_CLIENT_ID=<the web client id>.',
    );
  }

  final google = GoogleSignIn.instance;
  // Android cannot read the web client id from resources without a config file, so it
  // is handed over here.
  await google.initialize(serverClientId: serverClientId);

  final GoogleSignInAccount account;
  try {
    account = await google.authenticate();
  } on GoogleSignInException catch (e) {
    // Backing out of the sheet is a decision, not a fault. The plugin reports it as an
    // exception like any other, so it is separated here — everything above this line
    // treats null as "changed their mind" and a thrown error as "something broke".
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  }

  final idToken = account.authentication.idToken;
  if (idToken == null) return null;

  return idToken;
}
