import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Every non-customer account is one of these.
///
/// One enum, matching the one `staff` collection. What used to be two collections and two
/// rule sets is one of each, and this is the client half of that.
enum StaffRole { admin, moderator, owner, courier }

/// Whether an account belongs to the platform or to one merchant.
///
/// It decides reach, not rank: a platform courier serves home kitchens and merchants
/// that do not deliver, while a merchant courier only ever sees one kitchen's orders.
enum StaffScope { platform, merchant }

/// What the signed-in account is allowed to be, as the token states it.
///
/// Read off custom claims and never off a Firestore document. `firestore.rules` decides
/// ownership with `request.auth.token.merchantId`, and only a server can issue a claim;
/// a document field is something the client can attempt to write. Reading a document
/// here would leave the app and the rules answering one question from two sources, and
/// the disagreement would only ever surface as a permission error nobody can explain.
@immutable
class StaffIdentity {
  const StaffIdentity({
    this.uid,
    this.email,
    this.role,
    this.scope,
    this.merchantId,
    this.isAdmin = false,
  });

  static const none = StaffIdentity();

  final String? uid;
  final String? email;

  /// Null when the token carries no role, or one this build does not know about.
  final StaffRole? role;
  final StaffScope? scope;

  /// The merchant this account acts for, or null for a platform account.
  final String? merchantId;

  final bool isAdmin;

  /// Whether this account can actually act for a merchant.
  ///
  /// A merchant-scope claim with no `merchantId` signs in fine and then reads nothing.
  /// Distinguishing it here lets the app say so, instead of rendering an empty inbox
  /// that looks like a quiet evening.
  bool get ownsAMerchant => scope == StaffScope.merchant && merchantId != null;

  bool get isSignedIn => uid != null;

  static StaffIdentity from(LuqmaIdentity? identity) {
    if (identity == null) return none;

    final claims = identity.claims;
    final role = _enumFrom(StaffRole.values, claims['role']);

    return StaffIdentity(
      uid: identity.uid,
      email: identity.email,
      role: role,
      scope: _enumFrom(StaffScope.values, claims['scope']),
      merchantId: claims['merchantId'] is String
          ? claims['merchantId']! as String
          : null,
      // Either spelling counts. The rules check the bare `admin` flag, so the app has to
      // agree with them about who is one even on a token that carries nothing else.
      isAdmin: role == StaffRole.admin || claims['admin'] == true,
    );
  }

  /// Null for anything that is not one of [values] by name.
  ///
  /// A role added on the server before this build knew about it has to read as "no role".
  /// Throwing would take the app down over a value somebody typed in a console, and
  /// falling back to the first value would silently hand out whatever it happens to be.
  static T? _enumFrom<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }
}
