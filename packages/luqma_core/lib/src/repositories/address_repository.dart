import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/geography.dart';
import '../result.dart';

/// A customer's saved addresses.
///
/// They live under the customer's own user document — `users/{uid}/addresses` — which is
/// what lets the security rule be a single ownership check instead of a per-document one.
///
/// The default address lives on the user document rather than as a flag on each address:
/// a flag can be true on two of them at once, and then the app has to pick one and hide
/// the disagreement. One field can only ever name one.
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

class FirestoreAddressRepository implements AddressRepository {
  FirestoreAddressRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _addresses(String uid) =>
      _user(uid).collection('addresses');

  @override
  Future<Result<List<Address>>> addresses(String uid) {
    return Result.guard(() async {
      final snapshot = await _addresses(uid).get();
      return snapshot.docs
          .map((doc) => Address.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    });
  }

  @override
  Future<Result<Address>> saveAddress(String uid, Address address) {
    return Result.guard(() async {
      final collection = _addresses(uid);
      final isNew = address.id.isEmpty;
      final doc = isNew ? collection.doc() : collection.doc(address.id);
      final saved = address.copyWith(id: doc.id);

      await doc.set(saved.toJson()..remove('id'), SetOptions(merge: true));

      if (isNew) {
        final existing = await defaultAddressId(uid);
        if (existing.valueOrNull == null) {
          await setDefaultAddress(uid, doc.id);
        }
      }

      return saved;
    });
  }

  @override
  Future<Result<void>> deleteAddress(String uid, String addressId) {
    return Result.guard(() async {
      await _addresses(uid).doc(addressId).delete();

      // A default pointing at a deleted address renders as nothing at checkout, with
      // no way for the customer to tell what went wrong. A survivor takes over rather
      // than the default being cleared — being dropped back to "no address chosen"
      // because one of three was deleted makes them redo a choice already made.
      final current = await defaultAddressId(uid);
      if (current.valueOrNull == addressId) {
        final remaining = await addresses(uid);
        await _user(uid).set(
          {'defaultAddressId': remaining.valueOrNull?.firstOrNull?.id},
          SetOptions(merge: true),
        );
      }
    });
  }

  @override
  Future<Result<String?>> defaultAddressId(String uid) {
    return Result.guard(() async {
      final doc = await _user(uid).get();
      return doc.data()?['defaultAddressId'] as String?;
    });
  }

  @override
  Future<Result<void>> setDefaultAddress(String uid, String addressId) {
    return Result.guard(
      () => _user(uid).set(
        {'defaultAddressId': addressId},
        SetOptions(merge: true),
      ),
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
