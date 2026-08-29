import 'package:flutter_test/flutter_test.dart' show fail;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A client against the local stack, signed in as nobody in particular.
///
/// These tests reach the database through the same PostgREST endpoint the apps use, so
/// what they exercise is the repository *and* the policies in front of it — which is the
/// point. A repository that works against a fake and is refused by the boundary is the
/// exact failure the pre-launch audit found.
///
/// The service key is the local stack's, printed by `supabase start` and identical on
/// every machine. It is not a secret and belongs to nothing.
class LiveDatabase {
  LiveDatabase._(this.client);

  final SupabaseClient client;

  static const _url = String.fromEnvironment(
    'SUPABASE_URL',
    // 55321, not 54321: Windows reserves 54084-54683 for Hyper-V on this machine, so the
    // whole stack sits 1000 above. See supabase/config.toml.
    defaultValue: 'http://127.0.0.1:55321',
  );

  static const _serviceKey = String.fromEnvironment(
    'SUPABASE_SERVICE_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.'
        'EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU',
  );

  static const _anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.'
        'CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
  );

  /// A client with no more privilege than a phone in somebody's hand.
  ///
  /// Signing up is a public act, and the service key would answer a different question:
  /// whether an *administrator* can make an account, which nobody doubted.
  ///
  /// The storage is what keeps this on the app's own path. `Supabase.initialize` gives
  /// the real client one and GoTrue then defaults to PKCE; a bare client has none, and
  /// PKCE asserts rather than falling back — so without this the test would have to run
  /// the implicit flow, and prove sign-up works down a road the app never takes.
  SupabaseClient openAnonymously() => SupabaseClient(
        _url,
        _anonKey,
        authOptions: AuthClientOptions(pkceAsyncStorage: _MemoryAuthStorage()),
      );

  /// Opens a client that bypasses the boundary.
  ///
  /// Right for a repository test, which is asking whether the *query* is correct. Whether
  /// the boundary holds is asked in `supabase/test/stack`, against real tokens, and
  /// conflating the two produces a test that fails for whichever reason came first.
  static Future<LiveDatabase> open() async {
    return LiveDatabase._(SupabaseClient(_url, _serviceKey));
  }

  /// A second client signed in as a customer, with their users row beside them.
  ///
  /// Returns the client and the uid: the client talks to the database exactly as the
  /// app does, and the uid is what the tests seed against.
  Future<(SupabaseClient, String)> openAsCustomer() async {
    final unique = DateTime.now().microsecondsSinceEpoch;
    final email = 'cust-$unique@luqma.test';
    final created = await client.auth.admin.createUser(
      AdminUserAttributes(
        email: email,
        password: 'luqma1234',
        emailConfirm: true,
      ),
    );
    final uid = created.user!.id;
    // `ensure_user_profile` fires on every insert into auth.users, so the row is already
    // there. Upserting keeps this harness working either way rather than depending on
    // which of the two got there first.
    await client.from('users').upsert({'id': uid});

    final signedIn = SupabaseClient(_url, _serviceKey);
    await signedIn.auth.signInWithPassword(email: email, password: 'luqma1234');
    return (signedIn, uid);
  }

  /// A client signed in as a staff account of [role] under [scope], bound to
  /// [merchantId] when the scope is a merchant's.
  ///
  /// The kitchen and courier screens run under these identities in production, and the
  /// order transition guards read exactly these claims out of the token.
  /// Returns the signed-in client and the staff member's uid.
  Future<(SupabaseClient, String)> openAsStaff({
    required String scope,
    required String role,
    String? merchantId,
  }) async {
    final unique = DateTime.now().microsecondsSinceEpoch;
    final email = 'staff-$unique@luqma.test';
    final created = await client.auth.admin.createUser(
      AdminUserAttributes(
        email: email,
        password: 'luqma1234',
        emailConfirm: true,
      ),
    );
    final uid = created.user!.id;
    await client.from('staff').insert({
      'uid': uid,
      'scope': scope,
      'role': role,
      'merchant_id': ?merchantId,
    });

    final signedIn = SupabaseClient(_url, _serviceKey);
    await signedIn.auth.signInWithPassword(email: email, password: 'luqma1234');
    return (signedIn, uid);
  }

  /// A second client signed in — for real, password and all — as a platform admin.
  ///
  /// AdminApp's writes (approving a merchant, setting its plan) are refused to everyone
  /// but an admin by the column guards, and the service key is not an admin: its token
  /// carries no such claim. So the tests that play AdminApp sign in as the staff account
  /// they would run under in production, and the boundary evaluates exactly the token
  /// production would hand it.
  Future<SupabaseClient> openAsAdmin() async {
    final unique = DateTime.now().microsecondsSinceEpoch;
    final email = 'admin-$unique@luqma.test';
    final created = await client.auth.admin.createUser(
      AdminUserAttributes(
        email: email,
        password: 'luqma1234',
        emailConfirm: true,
      ),
    );
    await client.from('staff').insert({
      'uid': created.user!.id,
      'scope': 'platform',
      'role': 'admin',
    });

    // Built on the same keys, but the sign-in swaps what every later request carries.
    final admin = SupabaseClient(_url, _serviceKey);
    await admin.auth.signInWithPassword(email: email, password: 'luqma1234');
    return admin;
  }

  Future<void> close() => client.dispose();

  /// A signed-up customer, with the `users` row the product expects beside it.
  ///
  /// Orders reference `auth.users`, so this cannot be faked with a uuid: a foreign key
  /// would refuse it, which is the point of the foreign key.
  Future<String> makeCustomer() async {
    final unique = DateTime.now().microsecondsSinceEpoch;
    final created = await client.auth.admin.createUser(
      AdminUserAttributes(
        email: 'live-$unique@luqma.test',
        password: 'luqma1234',
        emailConfirm: true,
      ),
    );

    final uid = created.user!.id;
    // `ensure_user_profile` fires on every insert into auth.users, so the row is already
    // there. Upserting keeps this harness working either way rather than depending on
    // which of the two got there first.
    await client.from('users').upsert({'id': uid});
    return uid;
  }

  /// Makes a city nothing else is using, so a run cannot collide with the seed or with
  /// the run before it.
  Future<String> makeCity() async {
    final id = 'live-${DateTime.now().microsecondsSinceEpoch}';
    await client.from('cities').insert({'id': id, 'name': 'مدينة اختبار'});
    return id;
  }

  /// Removes everything that hangs off [cityId], in dependency order — the suite has to
  /// be re-runnable, and a foreign key refuses a city that still has zones.
  Future<void> dropCity(String cityId) async {
    final merchants = await client.from('merchants').select('id').eq('city_id', cityId);
    final ids = merchants.map((m) => m['id'] as String).toList();

    if (ids.isNotEmpty) {
      await client.from('menu_items').delete().inFilter('merchant_id', ids);
      // Before the orders, and the ordering is the point rather than housekeeping:
      // `order_settlements.order_id` is `on delete restrict`, because a settlement is
      // evidence of a charge and deleting the order it belongs to would either strand
      // it or, under cascade, quietly destroy the record that a merchant was billed.
      // In the product nothing deletes an order at all; only a test does.
      await client.from('order_settlements').delete().inFilter('merchant_id', ids);
      // And the receipts, for the same reason and with the same `on delete restrict`:
      // a record that money changed hands must not be removable by deleting the shop it
      // was paid by.
      await client.from('commission_payments').delete().inFilter('merchant_id', ids);
    }
    for (final table in ['orders', 'promotions', 'daily_meals', 'coupons', 'merchants',
                         'landmarks', 'home_sections', 'zones']) {
      await client.from(table).delete().eq('city_id', cityId);
    }
    await client.from('cities').delete().eq('id', cityId);
  }
}

/// Polls until [condition] holds or [timeout] passes, then fails the test.
///
/// For live streams, whose second emission arrives over a websocket on no schedule a
/// test can await deterministically.
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String because = 'the stream never reached the expected state',
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail(because);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Auth storage that lives as long as the test does.
///
/// PKCE needs somewhere to keep a code verifier between the request and the reply. On a
/// phone that is shared_preferences; here it is a map, because a test that leaves files
/// behind on disk is a test whose second run differs from its first.
class _MemoryAuthStorage extends GotrueAsyncStorage {
  final _items = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _items[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _items.remove(key);
  }
}
