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

  /// Opens a client that bypasses the boundary.
  ///
  /// Right for a repository test, which is asking whether the *query* is correct. Whether
  /// the boundary holds is asked in `supabase/test/stack`, against real tokens, and
  /// conflating the two produces a test that fails for whichever reason came first.
  static Future<LiveDatabase> open() async {
    return LiveDatabase._(SupabaseClient(_url, _serviceKey));
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
    await client.from('users').insert({'id': uid});
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
    }
    for (final table in ['orders', 'promotions', 'daily_meals', 'coupons', 'merchants',
                         'landmarks', 'home_sections', 'zones']) {
      await client.from(table).delete().eq('city_id', cityId);
    }
    await client.from('cities').delete().eq('id', cityId);
  }
}
