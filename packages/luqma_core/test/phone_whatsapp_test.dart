import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Turning whatever the owner typed into a number `wa.me` will accept.
///
/// The support number is typed once, in AdminApp, by a person — and every spelling of it
/// is one they might reasonably use: the local `01…`, the international `+20…`, the
/// `0020…` they read off a business card, or one with spaces in it. `wa.me` takes exactly
/// one of those shapes and answers a page saying the number is invalid for the rest, so
/// the folding has to happen here rather than being trusted to the typing.
void main() {
  test('a local number becomes an international one', () {
    expect(Phone.toWhatsapp('01012345678'), '201012345678');
  });

  test('a number already carrying the country code is left as it is', () {
    expect(Phone.toWhatsapp('201012345678'), '201012345678');
  });

  test('a plus is dropped', () {
    expect(Phone.toWhatsapp('+201012345678'), '201012345678');
  });

  test('so is the 00 people read off a card', () {
    expect(Phone.toWhatsapp('00201012345678'), '201012345678');
  });

  test('spaces and hyphens are not part of a number', () {
    expect(Phone.toWhatsapp('010 1234-5678'), '201012345678');
  });

  test('Arabic-Indic digits are the same number', () {
    // The owner types on the same Arabic keyboard as everybody else.
    expect(Phone.toWhatsapp('٠١٠١٢٣٤٥٦٧٨'), '201012345678');
  });

  test('something that is not a number at all comes back empty', () {
    // Empty is what the account screen tests for: no tile rather than a tile that opens
    // WhatsApp on a page saying this number does not exist.
    expect(Phone.toWhatsapp('كلمنا'), '');
  });
}
