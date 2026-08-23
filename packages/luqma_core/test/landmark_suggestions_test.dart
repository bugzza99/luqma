import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The landmark list is not something anyone can write in advance — not even someone who
/// lives in Edku. It is built from what customers type when they cannot find their
/// landmark in it, which makes every unmatched note a small piece of local knowledge the
/// owner did not have.
///
/// This turns those notes into a list worth reading: folded so one place is one entry,
/// counted so the common ones surface, and filtered so places already on the map do not
/// come back as suggestions forever.
void main() {
  LandmarkNote note(String text, {String zoneId = 'z1'}) =>
      LandmarkNote(zoneId: zoneId, text: text);

  const existing = [
    Landmark(id: 'l1', cityId: 'edku', zoneId: 'z1', name: 'مسجد الفتح'),
  ];

  List<LandmarkSuggestion> suggest(
    List<LandmarkNote> notes, {
    List<Landmark> known = existing,
    int minCount = 2,
  }) =>
      LandmarkSuggestion.from(notes: notes, known: known, minCount: minCount);

  group('counting', () {
    test('a note typed twice is one suggestion counted twice', () {
      final result = suggest([note('صيدلية النور'), note('صيدلية النور')]);

      expect(result, hasLength(1));
      expect(result.single.count, 2);
    });

    // The whole reason the folding exists: three spellings of one pharmacy are one
    // pharmacy, not three suggestions nobody acts on.
    test('spellings of the same place are counted together', () {
      final result = suggest([
        note('صيدلية النور'),
        note('صيدليه النور'),
        note('  صيدلـية   النور '),
      ]);

      expect(result, hasLength(1));
      expect(result.single.count, 3);
    });

    test('the commonest spelling is the one offered', () {
      final result = suggest([
        note('صيدليه النور'),
        note('صيدلية النور'),
        note('صيدلية النور'),
      ]);

      expect(result.single.name, 'صيدلية النور');
    });

    test('the busiest suggestion comes first', () {
      final result = suggest([
        note('الفرن'),
        note('الفرن'),
        note('كافيه الركن'),
        note('كافيه الركن'),
        note('كافيه الركن'),
      ]);

      expect(result.map((s) => s.name), ['كافيه الركن', 'الفرن']);
    });
  });

  group('what is left out', () {
    test('a place already on the map', () {
      final result = suggest([note('مسجد الفتح'), note('مسجد الفتح')]);
      expect(result, isEmpty);
    });

    // Same landmark, spelled differently — still already on the map.
    test('a place already on the map, spelled differently', () {
      final result = suggest([note('مسجد الفتح'), note('مسجد الفتح')]
        ..addAll([note('مسجد الفتح')]));
      expect(result, isEmpty);
    });

    test('a landmark known in another zone is still new in this one', () {
      final result = suggest([
        note('مسجد الفتح', zoneId: 'z2'),
        note('مسجد الفتح', zoneId: 'z2'),
      ]);

      expect(result, hasLength(1));
      expect(result.single.zoneId, 'z2');
    });

    test('something typed only once, below the threshold', () {
      expect(suggest([note('محل العطارة')]), isEmpty);
    });

    test('a threshold of one lets single notes through', () {
      expect(suggest([note('محل العطارة')], minCount: 1), hasLength(1));
    });

    // "جنب" or "بجوار" alone is somebody who tapped the field and gave up.
    test('text too short to name anything', () {
      expect(suggest([note('جنب'), note('جنب'), note('.'), note('.')]), isEmpty);
    });

    test('an empty note', () {
      expect(suggest([note(''), note('   ')]), isEmpty);
    });
  });

  group('zones', () {
    test('the same text in two zones is two suggestions', () {
      final result = suggest([
        note('الفرن', zoneId: 'z1'),
        note('الفرن', zoneId: 'z1'),
        note('الفرن', zoneId: 'z2'),
        note('الفرن', zoneId: 'z2'),
      ]);

      expect(result, hasLength(2));
      expect(result.map((s) => s.zoneId).toSet(), {'z1', 'z2'});
    });

    test('a suggestion carries the zone it was typed in', () {
      final result = suggest([note('الفرن', zoneId: 'z3'), note('الفرن', zoneId: 'z3')]);
      expect(result.single.zoneId, 'z3');
    });
  });

  group('turning one into a landmark', () {
    test('it keeps the customer’s own spelling and its zone', () {
      final suggestion = suggest([note('كافيه الركن'), note('كافيه الركن')]).single;

      final landmark = suggestion.toLandmark(id: 'new1', cityId: 'edku');

      expect(landmark.id, 'new1');
      expect(landmark.cityId, 'edku');
      expect(landmark.zoneId, 'z1');
      expect(landmark.name, 'كافيه الركن');
    });
  });
}
