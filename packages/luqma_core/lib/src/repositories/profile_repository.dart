import 'package:supabase_flutter/supabase_flutter.dart';

import '../result.dart';

/// The signed-in customer's own profile row.
///
/// A separate interface from the admin's [CustomerRepository]: that one is an admin
/// moderating the whole city, this one is a customer writing their own name or phone.
/// The columns it may touch are exactly `users_guard_columns` (`name`, `phone`,
/// `fcm_tokens`, `default_address_id`), so this is an ordinary RLS-guarded update rather
/// than a server function — the only reason it is a repository is the seam, so a screen
/// above it never talks to the database.
abstract interface class ProfileRepository {
  /// Writes the customer's phone.
  ///
  /// Capturing a phone at checkout is the first write a brand-new account makes, which
  /// makes this the seam that depends on `ensure_user_profile` having created the row.
  Future<Result<void>> savePhone({required String uid, required String phone});
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<void>> savePhone({required String uid, required String phone}) {
    return Result.guard(
      () => _db.from('users').update({'phone': phone}).eq('id', uid),
    );
  }
}

/// In-memory profile, for tests and for running the app with no backend at all.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.failure});

  final Failure? failure;

  /// What [savePhone] wrote, for assertions.
  final Map<String, String> phones = {};

  @override
  Future<Result<void>> savePhone({required String uid, required String phone}) async {
    if (failure != null) return Result.err(failure!);
    phones[uid] = phone;
    return const Result.ok(null);
  }
}
