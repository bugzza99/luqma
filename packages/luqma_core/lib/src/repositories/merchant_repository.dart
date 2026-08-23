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

  /// Every merchant in the city, whatever their status.
  ///
  /// For AdminApp only. The ones waiting for approval are the reason that screen exists,
  /// and hiding suspended ones would remove the only place they could be reinstated.
  /// Sorted so anything needing a decision is at the top.
  Stream<List<Merchant>> watchAllMerchants({required String cityId});

  /// Creates or replaces. An empty id means create.
  Future<Result<Merchant>> saveMerchant(Merchant merchant);

  Future<Result<void>> setStatus(String id, MerchantStatus status);
}

/// Pending first, then approved, then suspended.
int _byAttentionThenName(Merchant a, Merchant b) {
  const order = {
    MerchantStatus.pending: 0,
    MerchantStatus.approved: 1,
    MerchantStatus.suspended: 2,
  };
  final byStatus = order[a.status]!.compareTo(order[b.status]!);
  return byStatus != 0 ? byStatus : a.name.compareTo(b.name);
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

  @override
  Stream<List<Merchant>> watchAllMerchants({required String cityId}) {
    return _merchants
        .where('cityId', isEqualTo: cityId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_toMerchant).toList()
          ..sort(_byAttentionThenName));
  }

  @override
  Future<Result<Merchant>> saveMerchant(Merchant merchant) {
    return Result.guard(() async {
      final doc = merchant.id.isEmpty ? _merchants.doc() : _merchants.doc(merchant.id);
      final saved = merchant.copyWith(id: doc.id);
      // Merged rather than replaced: fields the admin form does not carry — the rating,
      // the wallet balance, the plan — must survive an edit to the name.
      await doc.set(saved.toJson()..remove('id'), SetOptions(merge: true));
      return saved;
    });
  }

  @override
  Future<Result<void>> setStatus(String id, MerchantStatus status) {
    return Result.guard(
      () => _merchants.doc(id).update({'status': status.name}),
    );
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

  @override
  Stream<List<Merchant>> watchAllMerchants({required String cityId}) {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(
      _merchants.values.where((m) => m.cityId == cityId).toList()
        ..sort(_byAttentionThenName),
    );
  }

  @override
  Future<Result<Merchant>> saveMerchant(Merchant merchant) async {
    if (failure != null) return Result.err(failure!);
    final saved = merchant.id.isEmpty
        ? merchant.copyWith(id: 'merchant-${_merchants.length + 1}')
        : merchant;
    _merchants[saved.id] = saved;
    return Result.ok(saved);
  }

  @override
  Future<Result<void>> setStatus(String id, MerchantStatus status) async {
    if (failure != null) return Result.err(failure!);
    final merchant = _merchants[id];
    if (merchant == null) return const Result.err(NotFoundFailure());
    _merchants[id] = merchant.copyWith(status: status);
    return const Result.ok(null);
  }
}
