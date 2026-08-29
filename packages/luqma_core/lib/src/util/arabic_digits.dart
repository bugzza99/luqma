/// Folding Arabic-Indic digits to Western ones.
///
/// Lives in one place because it is needed wherever a person types a number that the
/// system stored in Western digits — a coupon code, a price — and the two are
/// indistinguishable on screen. A phone with an Arabic keyboard produces ٢٠٢٦ where the
/// stored value is 2026, and to the person holding it the app has simply stopped working.
abstract final class ArabicDigits {
  const ArabicDigits._();

  static const _digits = '٠١٢٣٤٥٦٧٨٩';

  /// Arabic decimal and thousands separators, which the same keyboard also produces.
  static const decimalSeparator = '٫';
  static const thousandsSeparator = '٬';

  static String fold(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final char = String.fromCharCode(rune);
      final digit = _digits.indexOf(char);
      buffer.write(digit >= 0 ? '$digit' : char);
    }
    return buffer.toString();
  }
}
