import 'package:flutter/material.dart';

/// The 4/8 spacing rhythm. Every gap, pad and inset comes from here.
abstract final class Space {
  const Space._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// Horizontal inset on every screen.
  static const gutter = 16.0;

  /// Vertical gap between two sections.
  static const section = 24.0;
}

abstract final class Radii {
  const Radii._();

  static const card = Radius.circular(12);
  static const field = Radius.circular(10);
  static const image = Radius.circular(12);
  static const sheet = Radius.circular(16);
  static const pill = Radius.circular(999);

  static const cardAll = BorderRadius.all(card);
  static const fieldAll = BorderRadius.all(field);
  static const imageAll = BorderRadius.all(image);
  static const pillAll = BorderRadius.all(pill);
  static const sheetTop = BorderRadius.vertical(top: sheet);
}

abstract final class Elevations {
  const Elevations._();

  /// Cards are white on cream with a soft shadow. Material's default elevations read
  /// as cheap against a warm palette, so we set our own.
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0F130B07), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0D130B07), blurRadius: 32, offset: Offset(0, 12)),
  ];

  static const cardPressed = <BoxShadow>[
    BoxShadow(color: Color(0x14130B07), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Shadows disappear on a dark ground; separation there comes from surface colour.
  static const none = <BoxShadow>[];
}

abstract final class Sizes {
  const Sizes._();

  /// Android's minimum touch target. Expand the hit area when the glyph is smaller.
  static const minTarget = 48.0;

  /// Minimum space between two adjacent targets.
  static const targetGap = 8.0;

  static const iconSm = 18.0;
  static const iconMd = 24.0;
  static const iconLg = 32.0;

  static const appBarHeight = 56.0;

  /// Every promotion banner slot, whatever the render mode. A fixed ratio is what stops
  /// the home screen jumping as banners rotate.
  static const bannerAspect = 3.0;
}
