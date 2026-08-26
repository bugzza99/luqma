import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// What the app believes about who signed in.
///
/// The access-token hook copies the staff record into the **token**. It does not touch
/// the user row — `raw_app_meta_data` there stays `{provider: email}` for ever. So an
/// identity built from `user.appMetadata` carries no role, no scope and no merchant, and
/// every gate in the product reads it as an ordinary customer.
///
/// That is not a subtle failure: it locks the owner out of AdminApp with "this account
/// has no permission", and it locked out every merchant too. The hook was verified live
/// and the policies were tested against real tokens; nobody had tested the one line that
/// carries a claim from the session into the app.
void main() {
  late LiveDatabase live;

  setUpAll(() async {
    live = await LiveDatabase.open();
  });

  tearDownAll(() => live.close());

  test('an admin signing in is an admin to the app', () async {
    final admin = await live.openAsAdmin();
    addTearDown(admin.dispose);

    final auth = SupabaseAuthService(admin);
    await auth.restore();
    final identity = auth.identity;

    expect(identity, isNotNull, reason: 'somebody is signed in');

    final staff = StaffIdentity.from(identity);
    expect(staff.isSignedIn, isTrue);
    expect(staff.isAdmin, isTrue,
        reason: 'the hook put admin on the token; the app has to read it from there');
  });

  test('a merchant owner arrives carrying their shop', () async {
    final cityId = await live.makeCity();
    addTearDown(() => live.dropCity(cityId));

    final zone = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'منطقة'})
        .select()
        .single()
        .then((r) => r['id'] as String);
    final merchantId = await live.client.from('merchants').insert({
      'city_id': cityId, 'type': 'restaurant', 'name': 'مطعم',
      'zone_id': zone, 'phone': '0100', 'status': 'approved',
    }).select().single().then((r) => r['id'] as String);

    final (client, _) = await live.openAsStaff(
      scope: 'merchant', role: 'owner', merchantId: merchantId,
    );
    addTearDown(client.dispose);

    final auth = SupabaseAuthService(client);
    await auth.restore();
    final staff = StaffIdentity.from(auth.identity);

    expect(staff.role, StaffRole.owner);
    expect(staff.merchantId, merchantId,
        reason: 'MerchantApp shows a shop by reading this, and nothing else');
    expect(staff.isAdmin, isFalse, reason: 'an owner is not an admin');
  });

  // The other half: a customer's token carries no app_metadata worth anything, and that
  // has to read as "ordinary person", never as an error.
  test('a customer is nobody in particular, and that is not a failure', () async {
    final (client, _) = await live.openAsCustomer();
    addTearDown(client.dispose);

    final auth = SupabaseAuthService(client);
    await auth.restore();
    final staff = StaffIdentity.from(auth.identity);

    expect(staff.isSignedIn, isTrue);
    expect(staff.isAdmin, isFalse);
    expect(staff.role, isNull);
    expect(staff.merchantId, isNull);
  });
}
