import 'package:flutter/foundation.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'places_controller.g.dart';

/// Everything the places screen shows, loaded together.
///
/// One state rather than three providers because the three depend on each other: a
/// suggestion is only a suggestion if no landmark already matches it, and it is only
/// readable if its zone is known. Loading them separately would let the screen render a
/// suggestion for a landmark that had just been added.
@immutable
class PlacesState {
  const PlacesState({
    required this.zones,
    required this.landmarks,
    required this.suggestions,
  });

  final List<Zone> zones;
  final List<Landmark> landmarks;
  final List<LandmarkSuggestion> suggestions;
}

@riverpod
class PlacesController extends _$PlacesController {
  @override
  Future<PlacesState> build() async {
    final repository = ref.watch(geographyRepositoryProvider);
    final cityId = ref.watch(currentCityProvider);

    final zones = (await repository.zones(cityId: cityId, includeInactive: true))
        .valueOrThrow;
    final landmarks = (await repository.landmarks(cityId: cityId)).valueOrThrow;
    final notes = (await repository.landmarkNotes(cityId: cityId)).valueOrThrow;

    return PlacesState(
      zones: zones,
      landmarks: landmarks,
      suggestions: LandmarkSuggestion.from(notes: notes, known: landmarks),
    );
  }

  Future<void> saveZone({
    Zone? existing,
    required String name,
    required int deliveryFee,
  }) async {
    final cityId = ref.read(currentCityProvider);
    await ref.read(geographyRepositoryProvider).saveZone(
          (existing ?? Zone(id: '', cityId: cityId, name: name)).copyWith(
            name: name,
            defaultDeliveryFee: deliveryFee,
          ),
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> saveLandmark({
    Landmark? existing,
    required String name,
    required String zoneId,
  }) async {
    final cityId = ref.read(currentCityProvider);
    await ref.read(geographyRepositoryProvider).saveLandmark(
          (existing ?? Landmark(id: '', cityId: cityId, zoneId: zoneId, name: name))
              .copyWith(name: name, zoneId: zoneId),
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> deleteLandmark(String landmarkId) async {
    await ref.read(geographyRepositoryProvider).deleteLandmark(landmarkId);
    ref.invalidateSelf();
    await future;
  }

  /// Promotes a place customers kept naming into a real landmark.
  ///
  /// Reloading afterwards is what makes it leave the suggestion list: it is now known, so
  /// the next pass filters it out. Nothing has to remember to remove it.
  Future<void> acceptSuggestion(LandmarkSuggestion suggestion) async {
    final cityId = ref.read(currentCityProvider);
    await ref.read(geographyRepositoryProvider).saveLandmark(
          suggestion.toLandmark(id: '', cityId: cityId),
        );
    ref.invalidateSelf();
    await future;
  }
}
