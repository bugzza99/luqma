import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/merchant.dart';
import '../result.dart';

/// Reading and writing merchants.
///
/// An interface rather than direct Firestore calls, for one reason that shapes the whole
/// project: it lets the screens above be built and tested without Firebase, an emulator
/// or a network. Tests that need a running backend get written once and then stop
/// getting written.
abstract interface class MerchantRepository {
  /// Merchants a customer may see: approved, in this city. Live — the list updates
  /// itself when the admin approves or suspends someone.
  Stream<List<Merchant>> watchMerchants({required String cityId});

  Future<Result<Merchant>> getMerchant(String id);

  /// Pauses order intake until [until], or clears the pause when null.
  Future<Result<void>> setPausedUntil(String id, DateTime? until);
}

class FirestoreMerchantRepository implements MerchantRepository {
  FirestoreMerchantRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _merchants =>
      _firestore.collection('merchants');

  @override
  Stream<List<Merchant>> watchMerchants({required String cityId}) {
    return _merchants
        .where('cityId', isEqualTo: cityId)
        .where('status', isEqualTo: MerchantStatus.approved.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_toMerchant).toList());
  }

  @override
  Future<Result<Merchant>> getMerchant(String id) {
    return Result.guard(() async {
      final doc = await _merchants.doc(id).get();
      if (!doc.exists) throw const NotFoundFailure();
      return _toMerchant(doc);
    });
  }

  @override
  Future<Result<void>> setPausedUntil(String id, DateTime? until) {
    return Result.guard(() async {
      await _merchants.doc(id).update({
        'pausedUntil': until == null ? FieldValue.delete() : Timestamp.fromDate(until),
      });
    });
  }

  Merchant _toMerchant(DocumentSnapshot<Map<String, dynamic>> doc) {
    // The document id wins over any `id` field, so a copied document can never claim to
    // be the one it was copied from.
    return Merchant.fromJson({...doc.data()!, 'id': doc.id});
  }
}

/// An in-memory merchant repository for tests and for building screens before the
/// backend exists.
///
/// It re-applies the same visibility rules as the Firestore query rather than returning
/// whatever it was given: a fake that is more permissive than production hides exactly
/// the bugs it was meant to catch.
class FakeMerchantRepository implements MerchantRepository {
  FakeMerchantRepository({List<Merchant> seed = const [], this.failure})
      : _merchants = {for (final m in seed) m.id: m};

  final Map<String, Merchant> _merchants;

  /// When set, every call fails with this — so the offline and permission paths can be
  /// exercised without unplugging anything.
  final Failure? failure;

  @override
  Stream<List<Merchant>> watchMerchants({required String cityId}) {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(
      _merchants.values
          .where((m) => m.cityId == cityId && m.status == MerchantStatus.approved)
          .toList(),
    );
  }

  @override
  Future<Result<Merchant>> getMerchant(String id) async {
    if (failure != null) return Result.err(failure!);
    final merchant = _merchants[id];
    if (merchant == null) return const Result.err(NotFoundFailure());
    return Result.ok(merchant);
  }

  @override
  Future<Result<void>> setPausedUntil(String id, DateTime? until) async {
    if (failure != null) return Result.err(failure!);
    final merchant = _merchants[id];
    if (merchant == null) return const Result.err(NotFoundFailure());
    _merchants[id] = merchant.copyWith(pausedUntil: until);
    return const Result.ok(null);
  }
}
