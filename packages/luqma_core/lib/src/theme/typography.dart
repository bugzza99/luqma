import 'package:flutter/material.dart';

/// Type tokens.
///
/// One family — Cairo, shipped as a single variable file — carries the whole hierarchy
/// through weight. Lemonada is not here and never will be: the wordmark is a vector
/// asset, so the display face is not an app font at all.
///
/// Arabic sits taller than Latin and carries diacritics, so the scale runs larger and
/// looser than a Latin scale of the same rank. Body text bottoms out at 15, not 14.
abstract final class LuqmaType {
  const LuqmaType._();

  static const family = 'Cairo';

  static const regular = 400.0;
  static const medium = 500.0;
  static const semibold = 600.0;
  static const bold = 700.0;
  static const black = 900.0;

  /// Cairo is variable, so weight is set as an axis value. Setting only [FontWeight]
  /// would leave the axis at its default and every weight would render the same.
  static TextStyle _style({
    required double size,
    required double weight,
    required double lineHeight,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      height: lineHeight,
      letterSpacing: letterSpacing,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation('wght', weight)],
    );
  }

  static final screenTitle = _style(size: 24, weight: bold, lineHeight: 1.35);
  static final sectionTitle = _style(size: 20, weight: bold, lineHeight: 1.40);
  static final cardTitle = _style(size: 17, weight: semibold, lineHeight: 1.40);
  static final button = _style(size: 16, weight: semibold, lineHeight: 1.20);
  static final body = _style(size: 15, weight: regular, lineHeight: 1.60);
  static final bodyStrong = _style(size: 15, weight: semibold, lineHeight: 1.60);
  static final bodySmall = _style(size: 13, weight: regular, lineHeight: 1.60);
  static final caption =
      _style(size: 12, weight: medium, lineHeight: 1.50, letterSpacing: 0.2);

  /// Prices use Western numerals and tabular figures so columns of them line up.
  static final price = _style(size: 18, weight: bold, lineHeight: 1.30)
      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static final priceSmall = _style(size: 14, weight: bold, lineHeight: 1.30)
      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// The merchant's order total, the single loudest number in any of the three apps.
  static final display = _style(size: 34, weight: black, lineHeight: 1.05)
      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: display.copyWith(color: primary),
      headlineMedium: screenTitle.copyWith(color: primary),
      titleLarge: sectionTitle.copyWith(color: primary),
      titleMedium: cardTitle.copyWith(color: primary),
      labelLarge: button,
      bodyLarge: body.copyWith(color: primary),
      bodyMedium: body.copyWith(color: primary),
      bodySmall: bodySmall.copyWith(color: secondary),
      labelSmall: caption.copyWith(color: secondary),
    );
  }
}
