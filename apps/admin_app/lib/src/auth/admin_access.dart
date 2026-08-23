import 'package:flutter/foundation.dart';

/// The routes AdminApp knows about.
///
/// Named rather than typed inline so the redirect below and the router agree by
/// construction — a redirect that points at a path the router does not serve is a blank
/// screen with no error.
abstract final class Routes {
  const Routes._();

  /// Shown while the session is still resolving.
  static const starting = '/starting';
  static const signIn = '/sign-in';
  static const noAccess = '/no-access';
  static const dashboard = '/';
  static const merchants = '/merchants';
  static const zones = '/zones';
  static const media = '/media';
  static const staff = '/staff';
}

/// Who is holding the phone, as far as the token says.
@immutable
class AdminIdentity {
  const AdminIdentity({required this.uid, required this.isAdmin, this.email});

  final String uid;

  /// From the `admin` custom claim on the ID token.
  ///
  /// A claim, not a Firestore field: a field is something a client can try to write, and
  /// the security rules would then be trusting a value the client supplied.
  final bool isAdmin;

  final String? email;
}

enum AdminAccess {
  /// The session has not resolved yet. Distinct from [signedOut] on purpose.
  unknown,
  signedOut,

  /// Signed in, but the token carries no admin claim.
  notAuthorised,
  granted;

  static AdminAccess from(AdminIdentity? identity) {
    if (identity == null) return AdminAccess.signedOut;
    return identity.isAdmin ? AdminAccess.granted : AdminAccess.notAuthorised;
  }
}

/// Where [access] should send someone currently at [location], or null to leave them be.
///
/// Every branch returns null when the destination is where they already are. Without
/// that, each redirect fires again on arrival and the app loops instead of rendering.
String? redirectFor({required AdminAccess access, required String location}) {
  final destination = switch (access) {
    // Never guess while the session is resolving. Sending an unresolved user to sign-in
    // flashes a login screen at an admin who is already signed in, on every launch.
    AdminAccess.unknown => Routes.starting,
    AdminAccess.signedOut => Routes.signIn,
    AdminAccess.notAuthorised => Routes.noAccess,
    // An admin belongs wherever they were going — except on the three gate screens,
    // which have nothing to say to them.
    AdminAccess.granted => const {Routes.signIn, Routes.noAccess, Routes.starting}
            .contains(location)
        ? Routes.dashboard
        : null,
  };

  return destination == location ? null : destination;
}
