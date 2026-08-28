import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'admin_access.dart';

part 'identity_provider.g.dart';

/// The single answer the router asks for.
///
/// Built on `currentIdentityProvider`, the same session seam CustomerApp and MerchantApp
/// read — one identity shape across all three apps, matching the one `staff` collection
/// they share. It follows token changes rather than sign-in alone, so a claim granted
/// while the app is open lets the admin in on the next refresh instead of at the next
/// cold start.
@Riverpod(keepAlive: true)
AdminAccess adminAccess(Ref ref) {
  return switch (ref.watch(currentIdentityProvider)) {
    AsyncData(:final value) => AdminAccess.from(StaffIdentity.from(value)),
    // Not knowing is its own state — treating it as signed out flashes a login screen at
    // an admin who is already signed in, every launch.
    AsyncLoading() => AdminAccess.unknown,
    // Being unable to read the session means nobody is signed in, never that somebody is.
    AsyncError() => AdminAccess.signedOut,
  };
}
