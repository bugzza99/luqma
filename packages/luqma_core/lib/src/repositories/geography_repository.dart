import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/geography.dart';
import '../result.dart';

/// Zones and landmarks — the addressing layer the admin maintains.
///
/// Both lists are small and change rarely, so they are fetched whole rather than queried
/// per screen. On a weak connection, one cached list beats a fresh query every time.
abstract interface class GeographyRepository {
  Future<Result<List<Zone>>> zones({required String cityId});
  Future<Result<List<Landmark>>> landmarks({required String cityId});
}

class FirestoreGeographyRepository implements GeographyRepository {
  FirestoreGeographyRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<Result<List<Zone>>> zones({required String cityId}) {
    return Result.guard(() async {
      final snapshot = await _firestore
          .collection('zones')
          .where('cityId', isEqualTo: cityId)
          .where('isActive', isEqualTo: true)
          .orderBy('sortOrder')
          .get();
      return snapshot.docs
          .map((doc) => Zone.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
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
}

class FakeGeographyRepository implements GeographyRepository {
  // The fields are private because the interface already claims the names `zones` and
  // `landmarks` for its methods.
  const FakeGeographyRepository({
    List<Zone> zones = const [],
    List<Landmark> landmarks = const [],
    this.failure,
  })  : _zones = zones,
        _landmarks = landmarks;

  final List<Zone> _zones;
  final List<Landmark> _landmarks;

  /// When set, both calls fail with this, so the offline path can be exercised.
  final Failure? failure;

  @override
  Future<Result<List<Zone>>> zones({required String cityId}) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_zones.where((z) => z.cityId == cityId).toList());
  }

  @override
  Future<Result<List<Landmark>>> landmarks({required String cityId}) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_landmarks.where((l) => l.cityId == cityId).toList());
  }
}
