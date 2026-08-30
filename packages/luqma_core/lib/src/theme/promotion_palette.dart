import 'dart:ui';

/// The grounds a text banner may sit on, and the ink that goes on each.
///
/// A merchant picking a colour is picking a *background*, and nothing anywhere asks them
/// what the writing should be — because that is the question they would get wrong. Yellow
/// on white is the banner they would build, and it is unreadable on a phone in the sun.
/// So the ink is derived here and stored nowhere: there is no combination of columns that
/// can hold pale words on a pale ground.
///
/// The swatches are the brand's own colours plus a few the brand does not carry, which
/// exist because a city of banners in one burgundy stops reading as a banner at all.
abstract final class PromotionPalette {
  const PromotionPalette._();

  /// What the picker offers, in the order it offers them.
  ///
  /// Deliberately short. Twenty swatches is a colour-picker, and a colour-picker on a
  /// merchant's phone produces twenty banners nobody can read; eight tested grounds
  /// produce eight that work.
  static const swatches = <String>[
    '#761812', // brand
    '#451410', // brand pressed
    '#D67F2B', // accent
    '#F5EBE2', // cream
    '#1B4332', // deep green
    '#0E3A5C', // deep blue
    '#130B07', // near-black
    '#8C1C4A', // plum
  ];

  /// The ink that reads on [background].
  ///
  /// Contrast against both candidates rather than a brightness threshold: the accent
  /// orange sits near the middle, and a fixed cut-off puts white on it — which is 3.03:1
  /// and is the exact mistake the badge rule in the design system exists to stop.
  static Color inkOn(Color background) {
    const light = Color(0xFFF5EBE2);
    const dark = Color(0xFF130B07);
    return _contrast(background, light) >= _contrast(background, dark) ? light : dark;
  }

  /// Reads `#RRGGBB`, and answers null to anything else.
  ///
  /// Null rather than a throw: this parses a value that came out of a database column,
  /// and a banner on the brand gradient is a better answer to a malformed one than a home
  /// screen that crashes.
  static Color? parse(String? hex) {
    if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
    final value = int.tryParse(hex.substring(1), radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  /// WCAG's ratio, on `computeLuminance` — which is that standard's own formula and is
  /// already in `dart:ui`. Spelling it out again here would be a second copy to keep
  /// right.
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
  }
}
