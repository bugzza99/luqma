import 'package:supabase_flutter/supabase_flutter.dart';

import '../result.dart';
import '../util/phone.dart';

/// The signed-in customer's own account.
///
/// A separate interface from the admin's [CustomerRepository]: that one is an admin
/// moderating the whole city, this one is a customer writing their own name or phone.
/// Ordinary profile edits stay behind RLS. Deletion is a server function because it has
/// to scrub retained order snapshots and remove the GoTrue user in one transaction; the
/// repository keeps both shapes behind the same seam so the screen never talks to the
/// database.
abstract interface class ProfileRepository {
  /// Writes the customer's phone.
  ///
  /// Capturing a phone at checkout is the first write a brand-new account makes, which
  /// makes this the seam that depends on `ensure_user_profile` having created the row.
  Future<Result<void>> savePhone({required String uid, required String phone});

  /// Whether this customer wants the marketing notifications.
  ///
  /// Order status is never gated on it. Somebody who turns the offers off is still told
  /// that their food was accepted and that it left the shop, because those are not
  /// advertising and silencing them would be a different promise than the one the switch
  /// makes.
  Future<Result<bool>> readMarketingPush({required String uid});

  Future<Result<void>> setMarketingPush({required String uid, required bool on});

  /// Permanently removes the signed-in customer's account.
  ///
  /// There is deliberately no uid: the server derives the only account this operation
  /// may touch from the caller's token.
  Future<Result<void>> deleteMyAccount();
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<void>> savePhone({required String uid, required String phone}) {
    return Result.guardWrite(
      // Normalised here rather than at the call site, because the call site already
      // looked correct: checkout validates with `Phone.isValidEgyptianMobile`, which
      // folds Arabic-Indic digits *inside itself* before matching — so `٠١٠…` passes
      // validation and then arrives here exactly as typed.
      //
      // Sign-up stores `010…`. Two spellings of one number on one account means the
      // admin's search finds nobody, and the number `place_order` stamps on the order is
      // whichever the customer last typed. This is the last place it can go wrong before
      // a courier is at a door unable to ring.
      () => _db
          .from('users')
          .update({'phone': Phone.normalize(phone)})
          .eq('id', uid)
          .select('id'),
      (_) {},
    );
  }

  @override
  Future<Result<bool>> readMarketingPush({required String uid}) {
    return Result.guard(() async {
      final row = await _db
          .from('users')
          .select('marketing_push')
          .eq('id', uid)
          .maybeSingle();
      // Missing means the row has not been written yet, and the column defaults to true
      // — so the honest answer for a brand-new account is the same one the server would
      // give, not `false`, which would draw the switch off and quietly disagree.
      return (row?['marketing_push'] as bool?) ?? true;
    });
  }

  @override
  Future<Result<void>> setMarketingPush({required String uid, required bool on}) {
    return Result.guardWrite(
      () => _db
          .from('users')
          .update({'marketing_push': on})
          .eq('id', uid)
          .select('id'),
      (_) {},
    );
  }

  @override
  Future<Result<void>> deleteMyAccount() {
    return Result.guard(() async {
      await _db.rpc('delete_my_account');
    });
  }
}

/// In-memory profile, for tests and for running the app with no backend at all.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({
    this.failure,
    this.writeFailure,
    this.isStaffAccount = false,
    this.accountId,
  });

  final Failure? failure;

  /// Fails only the writes, so a screen that reads a value and then fails to change it
  /// can be tested. Reading and writing failing together is the offline case; this is
  /// the one where the switch has already been drawn.
  final Failure? writeFailure;
  final bool isStaffAccount;

  /// A fake has no auth client to name its account, so the first write claims it unless
  /// a test supplies one. Once claimed, another uid is as absent as it is under RLS.
  String? accountId;

  bool accountDeleted = false;

  /// What [savePhone] wrote, for assertions.
  final Map<String, String> phones = {};

  /// Off is a deliberate choice somebody made; absent means they never touched it, and
  /// the column's default is on.
  final Map<String, bool> marketing = {};

  @override
  Future<Result<void>> savePhone({required String uid, required String phone}) async {
    if (failure != null) return Result.err(failure!);
    accountId ??= uid;
    if (accountId != uid) return const Result.err(NotFoundFailure());
    phones[uid] = phone;
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> readMarketingPush({required String uid}) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(marketing[uid] ?? true);
  }

  @override
  Future<Result<void>> setMarketingPush({
    required String uid,
    required bool on,
  }) async {
    final refused = failure ?? writeFailure;
    if (refused != null) return Result.err(refused);
    accountId ??= uid;
    if (accountId != uid) return const Result.err(NotFoundFailure());
    marketing[uid] = on;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteMyAccount() async {
    if (failure != null) return Result.err(failure!);
    if (accountDeleted) return const Result.ok(null);
    // The fake closes the same boundary as Postgres: a permissive fake would let the
    // customer screen promise an operation the real account is forbidden to perform.
    if (isStaffAccount) return const Result.err(PermissionFailure());

    phones.clear();
    accountDeleted = true;
    return const Result.ok(null);
  }
}
