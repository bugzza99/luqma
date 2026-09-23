import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// A phone captured at checkout has to be an Egyptian mobile, or the courier has nothing
/// to call. Whatever the keyboard produced, the rule is the same: `01` then nine digits.
void main() {
  group('what is accepted', () {
    test('a plain Egyptian mobile', () {
      expect(Phone.isValidEgyptianMobile('01012345678'), isTrue);
    });

    test('Arabic-Indic digits', () {
      expect(Phone.isValidEgyptianMobile('٠١٠١٢٣٤٥٦٧٨'), isTrue);
    });

    test('spaces and hyphens are ignored', () {
      expect(Phone.isValidEgyptianMobile('010 123 456 78'), isTrue);
      expect(Phone.isValidEgyptianMobile('010-1234-5678'), isTrue);
    });
  });

  group('what is refused', () {
    test('too short', () => expect(Phone.isValidEgyptianMobile('0112345678'), isFalse));
    test('too long', () => expect(Phone.isValidEgyptianMobile('011234567890'), isFalse));
    test('not an Egyptian mobile prefix', () {
      expect(Phone.isValidEgyptianMobile('02012345678'), isFalse);
    });
    test('letters', () => expect(Phone.isValidEgyptianMobile('0101234567x'), isFalse));
    test('empty', () => expect(Phone.isValidEgyptianMobile(''), isFalse));
  });

  /// The address GoTrue holds for a customer who signed up with a phone number.
  ///
  /// Nobody ever types or sees it. What matters is that it is the *same* address every
  /// time for the same number: two spellings mapping to two addresses is one person with
  /// two accounts, half their orders on each.
  group('toAccountEmail', () {
    test('is the number at the reserved domain', () {
      expect(Phone.toAccountEmail('01012345678'), '01012345678@phone.luqma.app');
    });

    test('every spelling of one number gives one address', () {
      const canonical = '01012345678@phone.luqma.app';

      expect(Phone.toAccountEmail('٠١٠١٢٣٤٥٦٧٨'), canonical);
      expect(Phone.toAccountEmail('010 123 456 78'), canonical);
      expect(Phone.toAccountEmail('010-1234-5678'), canonical);
      expect(Phone.toAccountEmail('  01012345678  '), canonical);
    });
  });

  // E11 / D12. The spellings a real number arrives in that were not folded.
  group('what a pasted or dictated number carries', () {
    test('the invisible direction marks a copied number brings with it', () {
      // U+200E / U+200F / U+202A..U+202E / U+2066..U+2069: Android and WhatsApp wrap a
      // number in these when it is copied out of right-to-left text. Invisible, so the
      // person sees a correct number the app refuses.
      expect(Phone.normalize('\u202A01012345678\u202C'), '01012345678');
      expect(Phone.normalize('\u200E010\u200F12345678\u2066'), '01012345678');
      expect(Phone.isValidEgyptianMobile('\u202A٠١٠١٢٣٤٥٦٧٨\u202C'), isTrue);
    });

    test('Persian digits, which some keyboards produce', () {
      expect(Phone.normalize('۰۱۰۱۲۳۴۵۶۷۸'), '01012345678');
    });

    test('the country code, in either of the ways people say it', () {
      expect(Phone.normalize('+20 10 1234 5678'), '01012345678');
      expect(Phone.normalize('0020 10 1234 5678'), '01012345678');
      expect(Phone.normalize('+201012345678'), '01012345678');
    });

    test('and one number is still one account address whichever of these it came as', () {
      expect(Phone.toAccountEmail('+20 10 1234 5678'), '01012345678@phone.luqma.app');
    });
  });
}
