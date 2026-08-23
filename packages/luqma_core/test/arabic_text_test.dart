import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Matching Arabic the way people actually type it.
///
/// The same place is written several ways by different people and none of them is wrong.
/// Without folding those together, a landmark typed forty times by forty customers looks
/// like four landmarks typed ten times each, and the suggestion list is useless.
void main() {
  group('folding the forms of alef', () {
    test('أ إ آ all match ا', () {
      expect(ArabicText.normalize('أحمد'), ArabicText.normalize('احمد'));
      expect(ArabicText.normalize('إدكو'), ArabicText.normalize('ادكو'));
      expect(ArabicText.normalize('آمنة'), ArabicText.normalize('امنة'));
    });
  });

  group('the endings people swap', () {
    // Nobody agrees on this one, and both spellings are read the same aloud.
    test('ة and ه match', () {
      expect(ArabicText.normalize('صيدلية'), ArabicText.normalize('صيدليه'));
    });

    test('ى and ي match', () {
      expect(ArabicText.normalize('مصطفى'), ArabicText.normalize('مصطفي'));
    });
  });

  group('what gets stripped', () {
    test('diacritics', () {
      expect(ArabicText.normalize('لُقْمَة'), ArabicText.normalize('لقمة'));
    });

    test('tatweel', () {
      expect(ArabicText.normalize('صيدلـــية'), ArabicText.normalize('صيدلية'));
    });

    test('extra spaces, inside and around', () {
      expect(ArabicText.normalize('  صيدلية   النور  '), ArabicText.normalize('صيدلية النور'));
    });
  });

  group('what is kept', () {
    // Folding is for matching, never for display. The customer's own spelling is what
    // goes on the map.
    test('two genuinely different places stay different', () {
      expect(
        ArabicText.normalize('صيدلية النور'),
        isNot(ArabicText.normalize('صيدلية الشفاء')),
      );
    });

    test('Arabic-Indic digits fold so a numbered place matches itself', () {
      expect(ArabicText.normalize('عمارة ٢٤'), ArabicText.normalize('عمارة 24'));
    });

    test('Latin is lower-cased rather than dropped', () {
      expect(ArabicText.normalize('Cafe Corner'), ArabicText.normalize('cafe  corner'));
    });
  });
}
