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
    // Unreadable refusals hide nothing rather than failing the screen.
    final dismissed = (await repository.dismissedSuggestions()).valueOrNull ?? const {};

    return PlacesState(
      zones: zones,
      landmarks: landmarks,
      suggestions: LandmarkSuggestion.from(
        notes: notes,
        known: landmarks,
        dismissed: dismissed,
      ),
    );
  }

  Future<Result<Zone>> saveZone({
    Zone? existing,
    required String name,
    required int deliveryFee,
  }) async {
    final cityId = ref.read(currentCityProvider);
    final result = await ref.read(geographyRepositoryProvider).saveZone(
          (existing ?? Zone(id: '', cityId: cityId, name: name)).copyWith(
            name: name,
            defaultDeliveryFee: deliveryFee,
          ),
        );
    if (result.isOk) {
      ref.invalidateSelf();
      await future;
    }
    return result;
  }

  Future<Result<Landmark>> saveLandmark({
    Landmark? existing,
    required String name,
    required String zoneId,
  }) async {
    final cityId = ref.read(currentCityProvider);
    final result = await ref.read(geographyRepositoryProvider).saveLandmark(
          (existing ?? Landmark(id: '', cityId: cityId, zoneId: zoneId, name: name))
              .copyWith(name: name, zoneId: zoneId),
        );
    if (result.isOk) {
      ref.invalidateSelf();
      await future;
    }
    return result;
  }

  Future<Result<void>> deleteLandmark(String landmarkId) async {
    final result =
        await ref.read(geographyRepositoryProvider).deleteLandmark(landmarkId);
    if (result.isOk) {
      ref.invalidateSelf();
      await future;
    }
    return result;
  }

  /// Turns a suggestion down for good. Reloading drops it from the list, and every later
  /// spelling of the same name in that zone stays dropped.
  Future<Result<void>> dismissSuggestion(LandmarkSuggestion suggestion) async {
    final result = await ref
        .read(geographyRepositoryProvider)
        .dismissSuggestion(suggestion.zoneId, suggestion.name);
    if (result.isOk) {
      ref.invalidateSelf();
      await future;
    }
    return result;
  }

  /// Promotes a place customers kept naming into a real landmark.
  ///
  /// Reloading afterwards is what makes it leave the suggestion list: it is now known, so
  /// the next pass filters it out. Nothing has to remember to remove it.
  Future<Result<Landmark>> acceptSuggestion(LandmarkSuggestion suggestion) async {
    final cityId = ref.read(currentCityProvider);
    final result = await ref.read(geographyRepositoryProvider).saveLandmark(
          suggestion.toLandmark(id: '', cityId: cityId),
        );
    if (result.isOk) {
      ref.invalidateSelf();
      await future;
    }
    return result;
  }
}
