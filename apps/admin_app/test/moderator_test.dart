import 'package:admin_app/src/app/router.dart';
import 'package:admin_app/src/auth/admin_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// What a moderator is shown.
///
/// The role has existed since Phase 2 and the gate only ever asked for an admin, so
/// creating one produced an account that opened nothing. It holds the `admin` claim now
/// — that is what lets them in at all — and the database refuses it the money, the roster
/// and the control plane
/// (`supabase/migrations/20261024000000_a_moderator_is_an_admin_except.sql`).
///
/// This layer decides what is *offered*. Nothing here keeps anybody out: a refusal is a
/// `PermissionFailure` from the server whatever the grid draws, and a tile that always
/// ends in that sentence is one somebody taps every day and learns nothing from.
void main() {
  const moderator = StaffIdentity(
    uid: 'u2',
    role: StaffRole.moderator,
    scope: StaffScope.platform,
    isAdmin: true,
  );
  const admin = StaffIdentity(
    uid: 'u1',
    role: StaffRole.admin,
    scope: StaffScope.platform,
    isAdmin: true,
  );

  // Every module a moderator is refused outright, rather than partly.
  const closed = [
    Routes.coupons,
    Routes.staff,
    Routes.courierBilling,
    Routes.subscriptions,
    Routes.plans,
    Routes.settings,
  ];

  group('the gate', () {
    test('lets a moderator in — the whole defect, in one assertion', () {
      expect(AdminAccess.from(moderator), AdminAccess.granted);
    });

    test('and still tells the two apart', () {
      expect(admin.isPlatformAdmin, isTrue);
      expect(moderator.isPlatformAdmin, isFalse);
    });

    // Older fakes and any legacy token carry the bare flag and no role. That has always
    // read as an admin, and narrowing it here would lock the owner out of their own app
    // over a claim shape rather than over a decision anybody took.
    test('a token with the flag and no role is an admin', () {
      expect(const StaffIdentity(uid: 'u3', isAdmin: true).isPlatformAdmin, isTrue);
    });

    // The pair is not one question asked twice: an identity that has not resolved is
    // neither, and that is what stops the rail shedding six modules while a token
    // refreshes. Grant on the first, take away on the second.
    test('an unresolved identity is neither', () {
      expect(StaffIdentity.none.isPlatformAdmin, isFalse);
      expect(StaffIdentity.none.isModerator, isFalse);
    });

    test('and a moderator is the one the grid asks about', () {
      expect(moderator.isModerator, isTrue);
      expect(admin.isModerator, isFalse);
    });
  });

  group('the grid', () {
    test('an admin is shown every module', () {
      final routes = modulesFor(admin).map((m) => m.route);
      for (final route in closed) {
        expect(routes, contains(route), reason: '$route belongs to an admin');
      }
    });

    test('a moderator is shown neither the till, the roster nor the control plane', () {
      final routes = modulesFor(moderator).map((m) => m.route);
      for (final route in closed) {
        expect(routes, isNot(contains(route)), reason: '$route would only refuse them');
      }
    });

    test('and is shown the work they are for', () {
      final routes = modulesFor(moderator).map((m) => m.route);
      // Photographs, complaints, banners and the shops themselves: moderating is the job
      // the role exists for, and a version of this that hid those would be worse than the
      // account that opened nothing.
      expect(routes, containsAll([
        Routes.media,
        Routes.issues,
        Routes.promotions,
        Routes.merchants,
        Routes.customers,
        Routes.applications,
      ]));
    });

    // The gate never builds this screen for somebody unidentified, but a token refresh
    // passes through that state — and a grid that flickered from eighteen tiles to twelve
    // and back would read as the app losing modules.
    test('an identity that has not resolved is shown everything', () {
      expect(modulesFor(StaffIdentity.none).length, modulesFor(admin).length);
    });

    test('the two lists differ by exactly those six', () {
      expect(
        modulesFor(admin).length - modulesFor(moderator).length,
        closed.length,
      );
    });
  });
}
