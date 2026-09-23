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
/// Read off the token claims and never off a row a client can reach. The RLS policies
/// decide ownership with `auth.jwt() -> app_metadata`, and only the access-token hook
/// can put anything there; a column is something a client can attempt to write. Reading
/// one here would leave the app and the policies answering the same question from two
/// sources, and the disagreement would surface only as a permission error nobody can
/// explain.
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

  /// Whether this account is an admin and not a moderator.
  ///
  /// [isAdmin] is the *gate* — a moderator carries the `admin` claim on purpose, because
  /// without it they sign into nothing. This is the narrower question, and it exists so
  /// no screen offers a door the database will shut: money, deletion, and the roster are
  /// refused to a moderator by triggers in
  /// `20261024000000_a_moderator_is_an_admin_except.sql`.
  ///
  /// It decides what is *shown*, never what is permitted. The claim is stamped from the
  /// `staff` row at sign-in and a demotion an hour ago is not in it yet; the server reads
  /// the row on every call, which is why it is the boundary and this is not.
  bool get isPlatformAdmin => isAdmin && role != StaffRole.moderator;

  /// Whether the token says this account is a moderator.
  ///
  /// The opposite of [isPlatformAdmin] on a *known* account, and deliberately not its
  /// negation: [StaffIdentity.none] is neither. Use this to take something away — hiding
  /// a module, dimming a control — and [isPlatformAdmin] to grant one, so an identity
  /// that has not resolved yet loses nothing and gains nothing.
  ///
  /// Asking the wrong one of the pair is visible rather than dangerous, because the
  /// server refuses a moderator whatever the screen drew. It reads as the grid briefly
  /// shedding six modules while a token refreshes.
  bool get isModerator => role == StaffRole.moderator;

  bool get isSignedIn => uid != null;

  /// Equal when every field is, because what this is compared for is "did anything a
  /// screen reads change".
  ///
  /// `staffIdentityProvider` builds a new one on every GoTrue event, and a token refresh
  /// is one — hourly on its own, and on every resume. Riverpod filters updates with `==`,
  /// so without this every refresh read as a new person: whatever was built from the
  /// identity was torn down and rebuilt with the same account, which for the courier's
  /// write queue meant two queues replaying the same cash writes and the «محصلش» banner
  /// disappearing by itself.
  @override
  bool operator ==(Object other) =>
      other is StaffIdentity &&
      other.uid == uid &&
      other.email == email &&
      other.role == role &&
      other.scope == scope &&
      other.merchantId == merchantId &&
      other.isAdmin == isAdmin;

  @override
  int get hashCode => Object.hash(uid, email, role, scope, merchantId, isAdmin);

  static StaffIdentity from(LuqmaIdentity? identity) {
    if (identity == null) return none;

    final claims = identity.claims;
    final role = _enumFrom(StaffRole.values, claims['role']);

    return StaffIdentity(
      uid: identity.uid,
      email: identity.email,
      role: role,
      scope: _enumFrom(StaffScope.values, claims['scope']),
      // The access-token hook (supabase/migrations/20260824040000_fix_access_token_hook.sql)
      // writes `merchant_id` in snake_case into app_metadata. Older fakes and any legacy
      // token still used `merchantId`, so both spellings count — snake_case first because
      // that is what a real sign-in produces today.
      merchantId:
          _stringClaim(claims, 'merchant_id') ?? _stringClaim(claims, 'merchantId'),
      // Either spelling counts. The rules check the bare `admin` flag, so the app has to
      // agree with them about who is one even on a token that carries nothing else.
      isAdmin: role == StaffRole.admin || claims['admin'] == true,
    );
  }

  /// A string claim, or null when the key is absent or of the wrong type.
  ///
  /// A claim of the wrong type is ignored rather than thrown on, so a token somebody
  /// typed in a console cannot crash the app over one field.
  static String? _stringClaim(Map<String, Object?> claims, String key) {
    final value = claims[key];
    return value is String ? value : null;
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
