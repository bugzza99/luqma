import 'app_localizations.dart' show LuqmaStrings;

/// Money formatting, kept next to the strings but out of the ARB.
///
/// A price is not a translatable sentence — it is a rule about when to show piastres and
/// what to call zero — so putting it in the ARB would invite a translator to change
/// arithmetic. Western numerals throughout: they scan faster and are what the successful
/// Egyptian apps use, even in otherwise fully Arabic interfaces.
extension LuqmaMoney on LuqmaStrings {
  /// Formats [piastres] as a price. 15000 becomes `150 ج`, 15050 becomes `150.50 ج`.
  String price(int piastres) {
    if (piastres == 0) return priceFree;
    final pounds = piastres ~/ 100;
    final remainder = piastres % 100;
    // Whole pounds are the common case and reading "150.00" everywhere adds noise to
    // every screen for the sake of the rare price that needs it.
    final amount = remainder == 0
        ? '$pounds'
        : '$pounds.${remainder.toString().padLeft(2, '0')}';
    return '$amount $currencySuffix';
  }
}
