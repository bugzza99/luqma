import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Who a non-customer account is, read off the token.
///
/// Off the token and never off a Firestore document: a field is something a client can
/// try to write, and `firestore.rules` decides ownership with
/// `request.auth.token.merchantId`. If the app trusted a document instead, the app and
/// the rules would be answering the same question from two different sources.
void main() {
  StaffIdentity read(Map<String, Object?> claims) => StaffIdentity.from(
        LuqmaIdentity(uid: 'u1', email: 'x@y.z', claims: claims),
      );

  group('a merchant owner', () {
    test('carries the merchant the rules will check', () {
      final staff = read({
        'role': 'owner',
        'scope': 'merchant',
        'merchantId': 'm1',
      });

      expect(staff.role, StaffRole.owner);
      expect(staff.scope, StaffScope.merchant);
      expect(staff.merchantId, 'm1');
      expect(staff.isAdmin, isFalse);
    });

    test('is not an owner of anything without a merchant id', () {
      // A claim like this signs in fine and then reads nothing, so the app has to be
      // able to say so rather than render an empty inbox that looks like a quiet day.
      final staff = read({'role': 'owner', 'scope': 'merchant'});

      expect(staff.merchantId, isNull);
      expect(staff.ownsAMerchant, isFalse);
    });
  });

  group('a courier', () {
    test('scoped to one merchant carries it', () {
      final staff = read({
        'role': 'courier',
        'scope': 'merchant',
        'merchantId': 'm1',
      });

      expect(staff.role, StaffRole.courier);
      expect(staff.merchantId, 'm1');
    });

    // A platform courier serves home kitchens and merchants that do not deliver, so it
    // belongs to no single merchant.
    test('on the platform belongs to no merchant', () {
      final staff = read({'role': 'courier', 'scope': 'platform'});

      expect(staff.scope, StaffScope.platform);
      expect(staff.merchantId, isNull);
    });
  });

  group('an admin', () {
    test('is recognised from the role', () {
      final staff = read({'role': 'admin', 'scope': 'platform', 'admin': true});
      expect(staff.isAdmin, isTrue);
    });

    // The rules check the `admin` claim, so the app must agree with them about who is
    // one — including for a token where only that flag was set.
    test('is recognised from the bare claim the rules check', () {
      final staff = read({'admin': true});
      expect(staff.isAdmin, isTrue);
    });
  });

  group('the real access-token hook shape', () {
    // The hook (supabase/migrations/20260824040000_fix_access_token_hook.sql) writes
    // app_metadata as jsonb_build_object('role', role, 'scope', scope), then adds
    // 'merchant_id' only when non-null and 'admin' only for admins. These cases mirror
    // that shape exactly — snake_case merchant_id, not camelCase.

    test('a merchant owner carries the snake_case merchant_id the hook writes', () {
      final staff = read({
        'role': 'owner',
        'scope': 'merchant',
        'merchant_id': 'm1',
      });

      expect(staff.role, StaffRole.owner);
      expect(staff.scope, StaffScope.merchant);
      expect(staff.merchantId, 'm1');
      expect(staff.isAdmin, isFalse);
    });

    test('a merchant courier carries the snake_case merchant_id', () {
      final staff = read({
        'role': 'courier',
        'scope': 'merchant',
        'merchant_id': 'm7',
      });

      expect(staff.role, StaffRole.courier);
      expect(staff.merchantId, 'm7');
      expect(staff.ownsAMerchant, isTrue);
    });

    test('an admin carries the bare admin flag the hook writes', () {
      final staff = read({'role': 'admin', 'scope': 'platform', 'admin': true});

      expect(staff.role, StaffRole.admin);
      expect(staff.isAdmin, isTrue);
    });
  });

  group('a token that says nothing useful', () {
    test('a customer is staff of nothing', () {
      final staff = read({});

      expect(staff.role, isNull);
      expect(staff.scope, isNull);
      expect(staff.isAdmin, isFalse);
      expect(staff.ownsAMerchant, isFalse);
    });

    // A role added on the server before this build knew about it must read as "no role",
    // never as a crash and never as a role this build happens to sort next to it.
    test('a role this build does not know is no role', () {
      final staff = read({'role': 'inspector', 'scope': 'platform'});

      expect(staff.role, isNull);
      expect(staff.isAdmin, isFalse);
    });

    test('a claim of the wrong type is ignored rather than thrown on', () {
      final staff = read({'role': 7, 'merchantId': false});

      expect(staff.role, isNull);
      expect(staff.merchantId, isNull);
    });
  });

  group('the session', () {
    test('claims reach the identity', () async {
      final auth = FakeAuthService(
        restoring: const LuqmaIdentity(
          uid: 'u1',
          claims: {'role': 'owner', 'scope': 'merchant', 'merchantId': 'm1'},
        ),
      );

      await auth.restore();

      expect(StaffIdentity.from(auth.identity!).merchantId, 'm1');
    });

    test('nobody signed in is nobody', () {
      expect(StaffIdentity.from(null).role, isNull);
      expect(StaffIdentity.from(null).uid, isNull);
    });
  });
}
