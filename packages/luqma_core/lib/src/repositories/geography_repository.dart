import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/geography.dart';
import '../models/landmark_suggestion.dart';
import '../result.dart';

/// Zones and landmarks — the addressing layer the admin maintains.
///
/// Both lists are small and change rarely, so they are fetched whole rather than queried
/// per screen. On a weak connection, one cached list beats a fresh query every time.
abstract interface class GeographyRepository {
  Future<Result<List<Zone>>> zones({required String cityId, bool includeInactive});
  Future<Result<List<Landmark>>> landmarks({required String cityId});

  /// Creates or replaces. An empty id means create.
  Future<Result<Zone>> saveZone(Zone zone);

  /// Zones are deactivated, never deleted: past orders carry a `zoneId`, and deleting the
  /// zone would leave those addresses without the field a courier reads first.
  Future<Result<void>> setZoneActive(String zoneId, bool isActive);

  Future<Result<Landmark>> saveLandmark(Landmark landmark);

  /// Landmarks can be deleted outright. An address keeps the landmark *name* it was saved
  /// with, so removing a wrong entry costs no history.
  Future<Result<void>> deleteLandmark(String landmarkId);

  /// The landmarks customers typed themselves on recent orders, because the list did not
  /// have theirs. The raw material for [LandmarkSuggestion].
  Future<Result<List<LandmarkNote>>> landmarkNotes({
    required String cityId,
    int limit,
  });
}

class FirestoreGeographyRepository implements GeographyRepository {
  FirestoreGeographyRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<List<Zone>>> zones({
    required String cityId,
    bool includeInactive = false,
  }) {
    return Result.guard(() async {
      Query<Map<String, dynamic>> query =
          _firestore.collection('zones').where('cityId', isEqualTo: cityId);
      if (!includeInactive) {
        query = query.where('isActive', isEqualTo: true);
      }
      final snapshot = await query.get();
      final zones = snapshot.docs
          .map((doc) => Zone.fromJson({...doc.data(), 'id': doc.id}))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return zones;
    });
  }

  @override
  Future<Result<List<Landmark>>> landmarks({required String cityId}) {
    return Result.guard(() async {
      final snapshot = await _firestore
          .collection('landmarks')
          .where('cityId', isEqualTo: cityId)
          .get();
      return snapshot.docs
          .map((doc) => Landmark.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    });
  }

  @override
  Future<Result<Zone>> saveZone(Zone zone) {
    return Result.guard(() async {
      final zones = _firestore.collection('zones');
      final doc = zone.id.isEmpty ? zones.doc() : zones.doc(zone.id);
      final saved = zone.copyWith(id: doc.id);
      await doc.set(saved.toJson()..remove('id'), SetOptions(merge: true));
      return saved;
    });
  }

  @override
  Future<Result<void>> setZoneActive(String zoneId, bool isActive) {
    return Result.guard(
      () => _firestore.collection('zones').doc(zoneId).update({'isActive': isActive}),
    );
  }

  @override
  Future<Result<Landmark>> saveLandmark(Landmark landmark) {
    return Result.guard(() async {
      final landmarks = _firestore.collection('landmarks');
      final doc = landmark.id.isEmpty ? landmarks.doc() : landmarks.doc(landmark.id);
      final saved = landmark.copyWith(id: doc.id);
      await doc.set(saved.toJson()..remove('id'), SetOptions(merge: true));
      return saved;
    });
  }

  @override
  Future<Result<void>> deleteLandmark(String landmarkId) {
    return Result.guard(
      () => _firestore.collection('landmarks').doc(landmarkId).delete(),
    );
  }

  @override
  Future<Result<List<LandmarkNote>>> landmarkNotes({
    required String cityId,
    int limit = 500,
  }) {
    return Result.guard(() async {
      final snapshot = await _firestore
          .collection('orders')
          .where('cityId', isEqualTo: cityId)
          .limit(limit)
          .get();

      final notes = <LandmarkNote>[];
      for (final doc in snapshot.docs) {
        final address = doc.data()['address'];
        if (address is! Map) continue;
        final note = address['landmarkNote'];
        // Orders that picked a listed landmark say nothing new; only the ones that had
        // to type their own are of any use here.
        if (note is! String || note.trim().isEmpty) continue;
        final zoneId = address['zoneId'] ?? doc.data()['zoneId'];
        if (zoneId is! String) continue;
        notes.add(LandmarkNote(zoneId: zoneId, text: note));
      }
      return notes;
    });
  }
}

/// In-memory geography, for tests and for building screens before the backend exists.
class FakeGeographyRepository implements GeographyRepository {
  FakeGeographyRepository({
    List<Zone> zones = const [],
    List<Landmark> landmarks = const [],
    List<LandmarkNote> notes = const [],
    this.failure,
  })  : _zones = List.of(zones),
        _landmarks = List.of(landmarks),
        _notes = List.of(notes);

  final List<Zone> _zones;
  final List<Landmark> _landmarks;
  final List<LandmarkNote> _notes;

  /// When set, every call fails with this, so the offline path can be exercised.
  final Failure? failure;

  int _nextId = 1;

  @override
  Future<Result<List<Zone>>> zones({
    required String cityId,
    bool includeInactive = false,
  }) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(
      _zones
          .where((z) => z.cityId == cityId && (includeInactive || z.isActive))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
    );
  }

  @override
  Future<Result<List<Landmark>>> landmarks({required String cityId}) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_landmarks.where((l) => l.cityId == cityId).toList());
  }

  @override
  Future<Result<Zone>> saveZone(Zone zone) async {
    if (failure != null) return Result.err(failure!);
    final saved = zone.id.isEmpty ? zone.copyWith(id: 'zone-${_nextId++}') : zone;
    _zones
      ..removeWhere((z) => z.id == saved.id)
      ..add(saved);
    return Result.ok(saved);
  }

  @override
  Future<Result<void>> setZoneActive(String zoneId, bool isActive) async {
    if (failure != null) return Result.err(failure!);
    final index = _zones.indexWhere((z) => z.id == zoneId);
    if (index < 0) return const Result.err(NotFoundFailure());
    _zones[index] = _zones[index].copyWith(isActive: isActive);
    return const Result.ok(null);
  }

  @override
  Future<Result<Landmark>> saveLandmark(Landmark landmark) async {
    if (failure != null) return Result.err(failure!);
    final saved =
        landmark.id.isEmpty ? landmark.copyWith(id: 'landmark-${_nextId++}') : landmark;
    _landmarks
      ..removeWhere((l) => l.id == saved.id)
      ..add(saved);
    return Result.ok(saved);
  }

  @override
  Future<Result<void>> deleteLandmark(String landmarkId) async {
    if (failure != null) return Result.err(failure!);
    _landmarks.removeWhere((l) => l.id == landmarkId);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<LandmarkNote>>> landmarkNotes({
    required String cityId,
    int limit = 500,
  }) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_notes.take(limit).toList());
  }
}
