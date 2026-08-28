import 'package:admin_app/src/auth/admin_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Who is allowed into AdminApp, and where each answer sends them.
///
/// The APK is not on any store, but that is obscurity, not security — anyone who is handed
/// the file can install it. What actually decides access is the admin claim on the token,
/// which only a server can issue, and which the security rules check independently. This
/// layer exists so the app shows the right screen, not so it keeps anyone out.
void main() {
  group('reading the identity', () {
    test('nobody signed in', () {
      expect(AdminAccess.from(StaffIdentity.none), AdminAccess.signedOut);
    });

    test('signed in with the claim', () {
      expect(
        AdminAccess.from(const StaffIdentity(uid: 'u1', isAdmin: true)),
        AdminAccess.granted,
      );
    });

    // A signed-in Google account is not an admin account. Someone who sideloads the APK
    // and signs in gets this, and the rules would refuse them anyway.
    test('signed in without the claim', () {
      expect(
        AdminAccess.from(const StaffIdentity(uid: 'u1')),
        AdminAccess.notAuthorised,
      );
    });

    // Signed in, real account, wrong app. Telling them to sign in when they already
    // have is the most confusing thing this gate could say.
    test('a merchant owner is turned away, not asked to sign in', () {
      expect(
        AdminAccess.from(
          const StaffIdentity(
            uid: 'u1',
            role: StaffRole.owner,
            scope: StaffScope.merchant,
            merchantId: 'm1',
          ),
        ),
        AdminAccess.notAuthorised,
      );
    });
  });

  group('where each answer sends you', () {
    String? go(AdminAccess access, String from) =>
        redirectFor(access: access, location: from);

    test('an unresolved session waits rather than guessing', () {
      // Redirecting to sign-in here would flash a login screen at an admin who is
      // already signed in, every single launch.
      expect(go(AdminAccess.unknown, '/'), Routes.starting);
    });

    test('signed out goes to sign-in', () {
      expect(go(AdminAccess.signedOut, '/'), Routes.signIn);
    });

    // The classic redirect loop: send the signed-out user to sign-in, then redirect them
    // again from sign-in because they are still signed out.
    test('signed out on the sign-in page stays put', () {
      expect(go(AdminAccess.signedOut, Routes.signIn), isNull);
    });

    test('an unresolved session on the starting page stays put', () {
      expect(go(AdminAccess.unknown, Routes.starting), isNull);
    });

    test('no claim goes to the no-access page', () {
      expect(go(AdminAccess.notAuthorised, '/'), Routes.noAccess);
    });

    test('no claim on the no-access page stays put', () {
      expect(go(AdminAccess.notAuthorised, Routes.noAccess), isNull);
    });

    test('an admin is taken off the sign-in page', () {
      expect(go(AdminAccess.granted, Routes.signIn), Routes.dashboard);
    });

    test('an admin who just got their claim leaves the no-access page', () {
      expect(go(AdminAccess.granted, Routes.noAccess), Routes.dashboard);
    });

    test('an admin already inside is left alone', () {
      expect(go(AdminAccess.granted, '/merchants'), isNull);
      expect(go(AdminAccess.granted, '/zones/abc'), isNull);
    });

    test('an admin on the starting page moves on to the dashboard', () {
      expect(go(AdminAccess.granted, Routes.starting), Routes.dashboard);
    });
  });
}
