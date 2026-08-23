import 'package:firebase_auth/firebase_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'admin_access.dart';

part 'identity_provider.g.dart';

/// Who is signed in, and whether the token says they are an admin.
///
/// Rebuilt whenever the token changes, not only when the user does: a claim granted while
/// the app is open arrives on the next token refresh, and the app should let them in then
/// rather than at the next cold start.
@Riverpod(keepAlive: true)
Stream<AdminIdentity?> adminIdentity(Ref ref) {
  return FirebaseAuth.instance.idTokenChanges().asyncMap((user) async {
    if (user == null) return null;
    final token = await user.getIdTokenResult();
    return AdminIdentity(
      uid: user.uid,
      // Read off the token, never off a Firestore document. A field is something a client
      // can try to write; a claim can only be issued by a server, which is what makes the
      // security rules able to trust it.
      isAdmin: token.claims?['admin'] == true,
      email: user.email,
    );
  });
}

/// The single answer the router asks for.
@Riverpod(keepAlive: true)
AdminAccess adminAccess(Ref ref) {
  final identity = ref.watch(adminIdentityProvider);
  return switch (identity) {
    AsyncData(:final value) => AdminAccess.from(value),
    // Not knowing is its own state — treating it as signed out flashes a login screen at
    // an admin who is already signed in, every launch.
    AsyncLoading() => AdminAccess.unknown,
    // Being unable to read the session means nobody is signed in, never that somebody is.
    AsyncError() => AdminAccess.signedOut,
  };
}
