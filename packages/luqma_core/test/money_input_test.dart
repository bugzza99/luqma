import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Prices are stored in piastres but typed in pounds, on a phone that may be producing
/// Arabic-Indic digits. Everything that can go wrong between "what the merchant typed"
/// and "what the courier collects" goes wrong here.
void main() {
  group('reading a typed price', () {
    test('whole pounds', () => expect(Money.parse('150'), 15000));
    test('pounds and piastres', () => expect(Money.parse('150.50'), 15050));
    test('a single decimal place', () => expect(Money.parse('150.5'), 15050));
    test('surrounding spaces', () => expect(Money.parse('  150  '), 15000));

    // The same trap as coupon codes: an Arabic keyboard types ١٥٠ and it looks identical
    // to 150 on screen. Refusing it would read to the merchant as the app being broken.
    test('Arabic-Indic digits', () => expect(Money.parse('١٥٠'), 15000));
    test('Arabic-Indic with a decimal', () => expect(Money.parse('١٥٠٫٥٠'), 15050));

    test('an Arabic thousands separator is ignored', () {
      expect(Money.parse('1,250'), 125000);
    });

    test('a leading currency word is ignored', () => expect(Money.parse('150 ج'), 15000));
  });

  group('what is refused', () {
    test('empty', () => expect(Money.parse(''), isNull));
    test('letters', () => expect(Money.parse('مية وخمسين'), isNull));
    test('negative', () => expect(Money.parse('-50'), isNull));

    // Three decimal places is not a price — it is a typo, and rounding it silently would
    // mean the merchant's menu says one thing and the courier collects another.
    test('more precision than a piastre', () => expect(Money.parse('150.555'), isNull));

    test('absurdly large', () => expect(Money.parse('99999999'), isNull));
  });

  group('round tripping', () {
    test('a parsed price formats back to what was typed', () {
      for (final typed in ['150', '150.50', '0.25', '1250']) {
        final piastres = Money.parse(typed)!;
        expect(Money.format(piastres), typed == '150' ? '150' : typed.replaceFirst(RegExp(r'^0+(?=\d)'), ''));
      }
    });

    test('zero is zero, not blank', () => expect(Money.format(0), '0'));
  });
}
