import 'arabic_digits.dart';

/// Folding Arabic into a form two spellings of the same thing can be compared in.
///
/// Used for matching only — never for display. Which spelling a customer used is their
/// own, and the map should carry it as they wrote it.
///
/// The problem this solves is concrete: the landmark list is meant to grow from what
/// customers type when they cannot find their landmark in it. If "صيدلية النور",
/// "صيدليه النور" and "صيدلـية النور" do not fold together, one place typed forty times
/// looks like three places typed a dozen times each, and the suggestion list is noise.
abstract final class ArabicText {
  const ArabicText._();

  /// Harakat and the other combining marks a keyboard can produce. Stripped because
  /// almost nobody types them, so their presence is an accident of one keyboard rather
  /// than a difference in what was meant.
  static final _diacritics = RegExp('[ً-ْٰـ]');

  static final _whitespace = RegExp(r'\s+');

  static const _folds = {
    'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا',
    // Read the same aloud, and nobody agrees which to write.
    'ة': 'ه',
    'ى': 'ي',
    'ؤ': 'و',
    'ئ': 'ي',
  };

  static String normalize(String raw) {
    var text = ArabicDigits.fold(raw).toLowerCase();
    text = text.replaceAll(_diacritics, '');
    for (final entry in _folds.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text.replaceAll(_whitespace, ' ').trim();
  }

  /// Whether two pieces of text name the same thing, allowing for how they were typed.
  static bool sameAs(String a, String b) => normalize(a) == normalize(b);
}
