import 'package:flutter/foundation.dart';

import '../util/arabic_text.dart';
import 'geography.dart';

/// A landmark a customer typed themselves, because the list did not have theirs.
///
/// Read off the addresses on real orders. Every one of these is a piece of local
/// knowledge nobody could have written down in advance.
@immutable
class LandmarkNote {
  const LandmarkNote({required this.zoneId, required this.text});

  final String zoneId;
  final String text;
}

/// A place customers keep naming that is not on the map yet.
@immutable
class LandmarkSuggestion {
  const LandmarkSuggestion({
    required this.zoneId,
    required this.name,
    required this.count,
  });

  final String zoneId;

  /// The spelling customers used most often. Their spelling, not a normalised one —
  /// folding is for matching, and what goes on the map should read the way people write it.
  final String name;

  /// How many orders named it.
  final int count;

  /// Shorter than this is somebody who tapped the field and gave up — "جنب", a full stop.
  static const _minLength = 4;

  /// Builds the suggestion list from [notes], leaving out anything already [known] in the
  /// same zone and anything named fewer than [minCount] times.
  static List<LandmarkSuggestion> from({
    required List<LandmarkNote> notes,
    required List<Landmark> known,
    int minCount = 2,
  }) {
    // What is already on the map, per zone, in folded form — so a landmark spelled one
    // way on the map and another way by a customer is still recognised as known.
    final onTheMap = <String, Set<String>>{};
    for (final landmark in known) {
      onTheMap
          .putIfAbsent(landmark.zoneId, () => <String>{})
          .add(ArabicText.normalize(landmark.name));
    }

    // Grouped by zone and folded text; the raw spellings are kept so the commonest can
    // be offered back.
    final groups = <({String zoneId, String folded}), Map<String, int>>{};

    for (final note in notes) {
      final text = note.text.trim();
      if (text.length < _minLength) continue;

      final folded = ArabicText.normalize(text);
      if (folded.length < _minLength) continue;
      if (onTheMap[note.zoneId]?.contains(folded) ?? false) continue;

      final spellings = groups.putIfAbsent(
        (zoneId: note.zoneId, folded: folded),
        () => <String, int>{},
      );
      spellings[text] = (spellings[text] ?? 0) + 1;
    }

    final suggestions = <LandmarkSuggestion>[];
    for (final entry in groups.entries) {
      final total = entry.value.values.reduce((a, b) => a + b);
      if (total < minCount) continue;

      final commonest = entry.value.entries.reduce(
        (a, b) => b.value > a.value ? b : a,
      );
      suggestions.add(LandmarkSuggestion(
        zoneId: entry.key.zoneId,
        name: commonest.key,
        count: total,
      ));
    }

    // Busiest first: those are the places the most couriers are already asking about.
    suggestions.sort((a, b) => b.count.compareTo(a.count));
    return suggestions;
  }

  Landmark toLandmark({required String id, required String cityId}) =>
      Landmark(id: id, cityId: cityId, zoneId: zoneId, name: name);
}
