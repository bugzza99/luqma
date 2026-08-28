import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../models/geography.dart';
import '../result.dart';

/// A customer's saved addresses.
///
/// They live in one `addresses` table carrying `user_id`, which is what lets the RLS
/// policy be a single ownership check instead of a per-row one.
///
/// The default address lives on the user's row rather than as a flag on each address:
/// a flag can be true on two of them at once, and then the app has to pick one and hide
/// the disagreement. One column can only ever name one. The customer may move it —
/// `users_guard_columns` allows exactly that — and nothing else on their row.
abstract interface class AddressRepository {
  Future<Result<List<Address>>> addresses(String uid);

  /// Creates or replaces. An empty [Address.id] means create.
  ///
  /// The first address a customer ever saves becomes their default, because a customer
  /// with exactly one address should never be asked to choose it.
  Future<Result<Address>> saveAddress(String uid, Address address);

  Future<Result<void>> deleteAddress(String uid, String addressId);

  Future<Result<String?>> defaultAddressId(String uid);

  Future<Result<void>> setDefaultAddress(String uid, String addressId);
}

class SupabaseAddressRepository implements AddressRepository {
  SupabaseAddressRepository(this._db);

  final SupabaseClient _db;

  /// The fields of [Address] that have a column behind them.
  ///
  /// The model carries `lat`/`lng` for an order's frozen copy of an address; a saved
  /// address is zone, landmark and words, so sending keys no column has would fail the
  /// write rather than quietly dropping them.
  static const _saved = [
    'zoneId', 'landmarkId', 'landmarkName', 'landmarkNote',
    'street', 'building', 'floor', 'apartment', 'label',
  ];

  Address _address(Map<String, dynamic> row) =>
      Address.fromJson(ColumnNames.toModel(row));

  Map<String, dynamic> _row(Address address) {
    final json = address.toJson();
    final row = ColumnNames.toRow({for (final f in _saved) f: json[f]});
    // An empty landmark id means "none" everywhere else in this codebase, and an empty
    // string is not a uuid — the column would refuse it before the policy ever spoke.
    if (row['landmark_id'] == '') row['landmark_id'] = null;
    return row;
  }

  @override
  Future<Result<List<Address>>> addresses(String uid) {
    return Result.guard(() async {
      final rows =
          await _db
              .from('addresses')
              .select()
              .eq('user_id', uid)
              // Newest first, and said out loud rather than inherited from the SDK's
              // default — a reader should not have to know that `order()` descends.
              .order('created_at', ascending: false);
      return rows.map(_address).toList();
    });
  }

  @override
  Future<Result<Address>> saveAddress(String uid, Address address) {
    return Result.guard(() async {
      final row = _row(address);
      final saved = address.id.isEmpty
          ? await _db
              .from('addresses')
              .insert({...row, 'user_id': uid})
              .select()
              .single()
          : await _db
              .from('addresses')
              .update(row)
              // Scoped by owner even under a client that bypasses the boundary: a
              // repository that edits by id alone would move another person's address
              // wherever the key is held.
              .eq('id', address.id)
              .eq('user_id', uid)
              .select()
              .single();
      final savedAddress = _address(saved);

      if (address.id.isEmpty) {
        final existing = await defaultAddressId(uid);
        if (existing.valueOrNull == null) {
          await setDefaultAddress(uid, savedAddress.id);
        }
      }

      return savedAddress;
    });
  }

  @override
  Future<Result<void>> deleteAddress(String uid, String addressId) {
    return Result.guard(() async {
      // Read before the delete, not after: the column's foreign key is `on delete set
      // null`, so losing the default is the database's doing before this code ever
      // looks. A survivor takes over rather than the default being cleared — being
      // dropped back to "no address chosen" because one of three was deleted makes
      // them redo a choice already made.
      final current = await defaultAddressId(uid);
      await _db
          .from('addresses')
          .delete()
          .eq('id', addressId)
          .eq('user_id', uid);

      if (current.valueOrNull == addressId) {
        final remaining = await addresses(uid);
        await _db.from('users').update({
          'default_address_id': remaining.valueOrNull?.firstOrNull?.id,
        }).eq('id', uid);
      }
    });
  }

  @override
  Future<Result<String?>> defaultAddressId(String uid) {
    return Result.guard(() async {
      final row = await _db
          .from('users')
          .select('default_address_id')
          .eq('id', uid)
          .maybeSingle();
      return row?['default_address_id'] as String?;
    });
  }

  @override
  Future<Result<void>> setDefaultAddress(String uid, String addressId) {
    return Result.guard(
      () => _db
          .from('users')
          .update({'default_address_id': addressId})
          .eq('id', uid),
    );
  }
}

/// In-memory addresses, for tests and for building screens before anyone signs in.
class FakeAddressRepository implements AddressRepository {
  FakeAddressRepository({
    Map<String, List<Address>> seed = const {},
    this.failure,
  }) : _byUser = {
          for (final entry in seed.entries) entry.key: List.of(entry.value),
        } {
    // Same rule as the real one: whoever was seeded first is the default, so a screen
    // under test behaves the way it will in the app.
    for (final entry in _byUser.entries) {
      if (entry.value.isNotEmpty) _defaults[entry.key] = entry.value.first.id;
    }
  }

  final Map<String, List<Address>> _byUser;
  final Map<String, String> _defaults = {};
  final Failure? failure;

  @override
  Future<Result<List<Address>>> addresses(String uid) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(List.of(_byUser[uid] ?? const []));
  }

  @override
  Future<Result<Address>> saveAddress(String uid, Address address) async {
    if (failure != null) return Result.err(failure!);

    final list = _byUser.putIfAbsent(uid, () => []);
    final isNew = address.id.isEmpty;
    final saved =
        isNew ? address.copyWith(id: 'address-${list.length + 1}') : address;

    final at = list.indexWhere((a) => a.id == saved.id);
    if (at >= 0) {
      list[at] = saved;
    } else {
      list.add(saved);
    }

    if (isNew) _defaults.putIfAbsent(uid, () => saved.id);
    return Result.ok(saved);
  }

  @override
  Future<Result<void>> deleteAddress(String uid, String addressId) async {
    if (failure != null) return Result.err(failure!);

    _byUser[uid]?.removeWhere((a) => a.id == addressId);
    if (_defaults[uid] == addressId) {
      final next = _byUser[uid]?.firstOrNull;
      if (next == null) {
        _defaults.remove(uid);
      } else {
        _defaults[uid] = next.id;
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<String?>> defaultAddressId(String uid) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_defaults[uid]);
  }

  @override
  Future<Result<void>> setDefaultAddress(String uid, String addressId) async {
    if (failure != null) return Result.err(failure!);
    _defaults[uid] = addressId;
    return const Result.ok(null);
  }
}
