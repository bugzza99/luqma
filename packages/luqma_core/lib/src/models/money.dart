import '../util/arabic_digits.dart';

/// Turning what a merchant types into the integer the courier collects.
///
/// Every price in the system is an integer number of piastres. The gap this class covers
/// is the one between that and a text field on a phone: pounds rather than piastres,
/// possibly Arabic-Indic digits, possibly with separators, possibly nonsense.
///
/// Nothing here rounds silently. A price the app cannot read exactly is refused, because
/// the alternative is a menu that says one figure and a courier who collects another.
abstract final class Money {
  const Money._();

  /// Anything above this is a typo, not a meal. Ten thousand pounds.
  static const _maxPiastres = 1000000;

  /// Reads a typed price into piastres, or null if it cannot be read exactly.
  static int? parse(String raw) {
    final normalized = ArabicDigits.fold(raw)
        // Arabic decimal separator and thousands separators, both of which a phone
        // keyboard offers and a merchant will use.
        .replaceAll(ArabicDigits.decimalSeparator, '.')
        .replaceAll(ArabicDigits.thousandsSeparator, '')
        .replaceAll(',', '')
        // The currency suffix, if they typed the whole thing as it reads on screen.
        .replaceAll('ج', '')
        .replaceAll('EGP', '')
        .trim();

    if (normalized.isEmpty) return null;
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(normalized)) return null;

    final parts = normalized.split('.');
    final pounds = int.tryParse(parts[0]);
    if (pounds == null) return null;

    final piastres = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0')); // "5" means fifty piastres, not five

    final total = pounds * 100 + piastres;
    return total > _maxPiastres ? null : total;
  }

  /// The inverse, for putting a stored price back into a text field. Whole pounds lose
  /// the decimals — a menu full of "150.00" is noise on every row.
  static String format(int piastres) {
    final pounds = piastres ~/ 100;
    final remainder = piastres % 100;
    if (remainder == 0) return '$pounds';
    return '$pounds.${remainder.toString().padLeft(2, '0')}';
  }
}
