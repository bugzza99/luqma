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

  /// One number, one spelling. Arabic-Indic digits folded, spaces and hyphens dropped —
  /// the latter being how a number is read back down a phone line.
  static String normalize(String raw) =>
      ArabicDigits.fold(raw.trim()).replaceAll(RegExp(r'[\s-]'), '');

  static bool isValidEgyptianMobile(String raw) =>
      _egyptianMobile.hasMatch(normalize(raw));

  /// The address GoTrue holds for a customer who signed up with a phone number.
  ///
  /// A customer's identity is their phone, but GoTrue's *phone* identity needs Twilio —
  /// it refuses to enable without an SMS provider, even when no code is ever sent. So the
  /// number is folded into an ordinary email identity, which needs no provider at all.
  /// Nobody types this address and nobody is shown it.
  ///
  /// [normalize] first, and that is the whole point: two spellings of one number mapping
  /// to two addresses is one person with two accounts and half their orders on each.
  ///
  /// The domain is reserved and holds no mailbox. Nothing is ever sent to it — email
  /// confirmation is off, and a customer who forgets their password is reset by an admin
  /// (there is no inbox to send a link to).
  static String toAccountEmail(String raw) => '${normalize(raw)}@$accountDomain';

  static const accountDomain = 'phone.luqma.app';

  /// The number in the shape `wa.me` accepts: country code, no plus, no leading zero.
  ///
  /// The support number is typed once by the owner in AdminApp and every spelling of it
  /// is one somebody would reasonably use — `01…`, `+20…`, `0020…`, with spaces. `wa.me`
  /// takes one of those and answers "phone number shared via url is invalid" for the
  /// rest, which reads as the support line being broken.
  ///
  /// Anything that is not a number comes back empty, and the caller draws no control at
  /// all rather than one that opens a page saying the number does not exist.
  static String toWhatsapp(String raw) {
    var digits = normalize(raw).replaceFirst(RegExp(r'^\+'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (RegExp(r'^[0-9]+$').hasMatch(digits) == false) return '';
    // A local `01…` gains the country code; anything that already starts with it keeps
    // what it has, so a number entered internationally is not mangled into `2020…`.
    if (digits.startsWith('0')) return '$_egypt${digits.substring(1)}';
    if (digits.startsWith(_egypt)) return digits;
    return '$_egypt$digits';
  }

  static const _egypt = '20';
}
