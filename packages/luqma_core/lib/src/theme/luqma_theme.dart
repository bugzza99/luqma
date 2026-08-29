import 'package:flutter/material.dart';

import 'colors.dart';
import 'dimens.dart';
import 'motion.dart';
import 'typography.dart';

/// Builds the two themes every Luqma app runs on.
///
/// Both are defined here rather than derived from one another: the dark palette was
/// measured, not inverted, and inverting it would quietly break the contrast the tests
/// in this package assert.
abstract final class LuqmaTheme {
  const LuqmaTheme._();

  static ThemeData get light => _build(LuqmaColors.light, Brightness.light);
  static ThemeData get dark => _build(LuqmaColors.dark, Brightness.dark);

  static ThemeData _build(LuqmaColors c, Brightness brightness) {
    final text = LuqmaType.textTheme(c.textPrimary, c.textSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      extensions: [c],
      fontFamily: LuqmaType.family,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      dividerColor: c.hairline,
      splashFactory: InkSparkle.splashFactory,
      textTheme: text,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.brand,
        onPrimary: c.onBrand,
        secondary: c.accent,
        onSecondary: c.onAccent,
        error: c.danger,
        onError: c.onBrand,
        surface: c.card,
        onSurface: c.textPrimary,
        surfaceContainerHighest: c.surface,
        outline: c.border,
        outlineVariant: c.hairline,
        scrim: c.scrim,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.brand,
        foregroundColor: c.onBrand,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: Sizes.appBarHeight,
        titleTextStyle: LuqmaType.cardTitle.copyWith(color: c.onBrand),
      ),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.cardAll,
          side: BorderSide(color: c.hairline),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          textStyle: LuqmaType.button,
          shape: const RoundedRectangleBorder(borderRadius: Radii.fieldAll),
          animationDuration: Motion.tap,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.brand,
          side: BorderSide(color: c.border, width: 1.5),
          minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          textStyle: LuqmaType.button,
          shape: const RoundedRectangleBorder(borderRadius: Radii.fieldAll),
          animationDuration: Motion.tap,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.brand,
          minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
          textStyle: LuqmaType.button,
          animationDuration: Motion.tap,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        hintStyle: LuqmaType.body.copyWith(color: c.textSecondary),
        labelStyle: LuqmaType.bodySmall.copyWith(color: c.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        border: OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide(color: c.brand, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.fieldAll,
          borderSide: BorderSide(color: c.danger, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.card,
        selectedItemColor: c.brand,
        unselectedItemColor: c.textSecondary,
        selectedLabelStyle: LuqmaType.caption,
        unselectedLabelStyle: LuqmaType.caption,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.card,
        selectedColor: c.brand,
        side: BorderSide(color: c.border),
        labelStyle: LuqmaType.bodySmall.copyWith(color: c.textSecondary),
        secondaryLabelStyle: LuqmaType.bodySmall.copyWith(color: c.onBrand),
        shape: const RoundedRectangleBorder(borderRadius: Radii.pillAll),
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.textPrimary,
        contentTextStyle: LuqmaType.body.copyWith(color: c.background),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: Radii.fieldAll),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
