import 'arabic_digits.dart';

/// Whether a typed number is an Egyptian mobile phone number.
///
/// `01` followed by exactly nine digits. Arabic-Indic digits are folded first — the same
/// trap as prices and coupon codes: a phone with an Arabic keyboard types ٠١٠١٢٣٤٥٦٧٨
/// where the stored value is 01012345678, and to the person holding it the app has simply
/// stopped working.
abstract final class Phone {
  const Phone._();

  static final _egyptianMobile = RegExp(r'^01[0-9]{9}$');

  static bool isValidEgyptianMobile(String raw) {
    // Spaces and hyphens are how a number is read back down a phone line, so they are
    // ignored — the same normalization the admin's customer search uses.
    final normalized = ArabicDigits.fold(raw).replaceAll(RegExp(r'[\s-]'), '');
    return _egyptianMobile.hasMatch(normalized);
  }
}
