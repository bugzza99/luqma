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
}
