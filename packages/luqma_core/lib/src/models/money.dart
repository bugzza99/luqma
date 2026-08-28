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
    var normalized = ArabicDigits.fold(raw)
        // The Arabic decimal separator becomes a dot; the Arabic thousands separator is
        // folded into the same comma as the Western one, so both keyboards get the same
        // grouping rule below.
        .replaceAll(ArabicDigits.decimalSeparator, '.')
        .replaceAll(ArabicDigits.thousandsSeparator, ',')
        // The currency suffix, if they typed the whole thing as it reads on screen.
        .replaceAll('ج', '')
        .replaceAll('EGP', '')
        .trim();

    if (normalized.isEmpty) return null;

    // A comma is a thousands separator, never a decimal point, so it must sit in strict
    // groups of three: "1,5" is not a price, "1,500" is. Stripping every comma was how
    // "1,5" read as fifteen pounds — one keystroke's difference from "1.5", worth a
    // factor of ten at the till.
    if (normalized.contains(',')) {
      if (!RegExp(r'^\d{1,3}(,\d{3})+(\.\d{1,2})?$').hasMatch(normalized)) {
        return null;
      }
      normalized = normalized.replaceAll(',', '');
    }

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
    // A negative balance is not a price a person can be shown: the only money on a
    // screen is what the courier collects, which is never negative. Guarded rather than
    // thrown so a stray negative never takes a screen down over a value it cannot render.
    if (piastres < 0) return '0';

    final pounds = piastres ~/ 100;
    final remainder = piastres % 100;
    if (remainder == 0) return '$pounds';
    return '$pounds.${remainder.toString().padLeft(2, '0')}';
  }
}
