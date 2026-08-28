import 'package:flutter/material.dart';

/// The raw brand palette from `docs/14-design-system.md`.
///
/// Screens never reference these. They read [LuqmaColors] off the theme, which maps
/// each swatch to a role and swaps the mapping between light and dark.
abstract final class LuqmaPalette {
  const LuqmaPalette._();

  // Brand
  static const burgundy = Color(0xFF761812);
  static const burgundyDark = Color(0xFF451410);
  static const burgundyLight = Color(0xFF8F2019); // dark-theme brand; burgundy is too dark there
  static const orange = Color(0xFFD67F2B);
  static const orangeLight = Color(0xFFE69B4A);

  /// Deeper orange for text. [orange] scores 2.58:1 on [cream] and fails; this passes
  /// on both cream and white, at the same hue.
  static const orangeText = Color(0xFF995A1D);

  // Ground
  static const cream = Color(0xFFF5EBE2);
  static const surface = Color(0xFFE5D3C1);
  static const white = Color(0xFFFFFFFF);

  // Ink
  static const ink = Color(0xFF130B07);
  static const inkSoft = Color(0xFF5A452B);

  // Lines. [hairline] is decorative only — it scores 1.5:1 on cream, far under the 3:1
  // a meaningful boundary needs. Interactive outlines use [edge].
  static const hairline = Color(0xFFD6BFA9);
  static const edge = Color(0xFFA5794F);

  // Dark theme ground
  static const darkBg = Color(0xFF150C08);
  static const darkSurface = Color(0xFF241610);
  static const darkSurfaceHigh = Color(0xFF33211A);
  static const darkTextSoft = Color(0xFFC9B3A0);
  static const darkHairline = Color(0xFF3E2A21);
  static const darkEdge = Color(0xFF8A6A55);

  // Status. Only two colours beyond the brand set, both required to express order state.
  // [danger] is a brighter red than the burgundy so the two do not read as the same thing;
  // even so, a destructive control always carries an icon and explicit wording, never
  // colour alone.
  static const success = Color(0xFF1E7A43);
  static const successDark = Color(0xFF5FC98A);
  static const danger = Color(0xFFC0342B);
  static const dangerDark = Color(0xFFF0847A);
}

/// Semantic colour roles. Read with `Theme.of(context).luqma`.
@immutable
class LuqmaColors extends ThemeExtension<LuqmaColors> {
  const LuqmaColors({
    required this.background,
    required this.surface,
    required this.card,
    required this.hairline,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.brand,
    required this.brandPressed,
    required this.onBrand,
    required this.accent,
    required this.onAccent,
    required this.price,
    required this.success,
    required this.danger,
    required this.scrim,
  });

  /// Page ground. 60% of the screen.
  final Color background;

  /// Grouped rows, skeletons, section bands — on [card], not on [background],
  /// where it is effectively invisible.
  final Color surface;

  /// Cards sit on [background] as this colour plus a soft shadow.
  final Color card;

  /// Decorative separators only.
  final Color hairline;

  /// Outlines that carry meaning: fields, unselected chips, checkbox frames.
  final Color border;

  final Color textPrimary;
  final Color textSecondary;

  final Color brand;
  final Color brandPressed;
  final Color onBrand;

  /// Prices, offers, ratings, promotional highlights — and nothing else. The moment
  /// this becomes a general-purpose colour it stops signalling value.
  final Color accent;

  /// Text and icons on an [accent] fill. Dark, never white: white scores 3.03:1 there.
  final Color onAccent;

  /// Accent tuned for text. Use for any price below 18sp or on [background].
  final Color price;

  final Color success;
  final Color danger;
  final Color scrim;

  static const light = LuqmaColors(
    background: LuqmaPalette.cream,
    surface: LuqmaPalette.surface,
    card: LuqmaPalette.white,
    hairline: LuqmaPalette.hairline,
    border: LuqmaPalette.edge,
    textPrimary: LuqmaPalette.ink,
    textSecondary: LuqmaPalette.inkSoft,
    brand: LuqmaPalette.burgundy,
    brandPressed: LuqmaPalette.burgundyDark,
    onBrand: LuqmaPalette.white,
    accent: LuqmaPalette.orange,
    onAccent: LuqmaPalette.ink,
    price: LuqmaPalette.orangeText,
    success: LuqmaPalette.success,
    danger: LuqmaPalette.danger,
    scrim: Color(0x99130B07),
  );

  static const dark = LuqmaColors(
    background: LuqmaPalette.darkBg,
    surface: LuqmaPalette.darkSurfaceHigh,
    card: LuqmaPalette.darkSurface,
    hairline: LuqmaPalette.darkHairline,
    border: LuqmaPalette.darkEdge,
    textPrimary: LuqmaPalette.cream,
    textSecondary: LuqmaPalette.darkTextSoft,
    brand: LuqmaPalette.burgundyLight,
    brandPressed: LuqmaPalette.burgundy,
    onBrand: LuqmaPalette.white,
    accent: LuqmaPalette.orangeLight,
    onAccent: LuqmaPalette.ink,
    price: LuqmaPalette.orangeLight,
    success: LuqmaPalette.successDark,
    danger: LuqmaPalette.dangerDark,
    scrim: Color(0xB3000000),
  );

  @override
  LuqmaColors copyWith({
    Color? background,
    Color? surface,
    Color? card,
    Color? hairline,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? brand,
    Color? brandPressed,
    Color? onBrand,
    Color? accent,
    Color? onAccent,
    Color? price,
    Color? success,
    Color? danger,
    Color? scrim,
  }) {
    return LuqmaColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      hairline: hairline ?? this.hairline,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      brand: brand ?? this.brand,
      brandPressed: brandPressed ?? this.brandPressed,
      onBrand: onBrand ?? this.onBrand,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      price: price ?? this.price,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  LuqmaColors lerp(ThemeExtension<LuqmaColors>? other, double t) {
    if (other is! LuqmaColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return LuqmaColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      card: mix(card, other.card),
      hairline: mix(hairline, other.hairline),
      border: mix(border, other.border),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      brand: mix(brand, other.brand),
      brandPressed: mix(brandPressed, other.brandPressed),
      onBrand: mix(onBrand, other.onBrand),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      price: mix(price, other.price),
      success: mix(success, other.success),
      danger: mix(danger, other.danger),
      scrim: mix(scrim, other.scrim),
    );
  }
}

extension LuqmaThemeAccess on ThemeData {
  /// The brand colour roles. Present on every theme this package builds.
  ///
  /// Fails with an explanation rather than a bare null-check error, because the only way
  /// to get here is a `ThemeData` that did not come from [LuqmaTheme] — almost always a
  /// widget test that reached for `MaterialApp()` without one.
  LuqmaColors get luqma {
    final colors = extension<LuqmaColors>();
    if (colors == null) {
      throw FlutterError(
        'This ThemeData carries no LuqmaColors. '
        'Build it with LuqmaTheme.light or LuqmaTheme.dark. In a widget test that '
        'means MaterialApp(theme: LuqmaTheme.light, ...).',
      );
    }
    return colors;
  }
}
