import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Which form of the logo to draw.
enum LuqmaLogo {
  /// Disc, bite and carved ل, with the orange crumb.
  mark,

  /// The mark without the crumb. Use below 48dp, where the crumb reads as dust.
  markSmall,

  /// The name alone.
  wordmark,

  /// Mark and name side by side. The general-purpose lockup.
  horizontal,

  /// The horizontal lockup drawn in cream, sized for an app bar.
  appBar,

  /// Mark above name on a burgundy panel. The splash and store form.
  stacked,
}

/// The Luqma brand name, drawn from vector assets.
///
/// The name is never a `Text` widget. Lemonada is not bundled as an app font, so typing
/// the name would render it in Cairo and quietly lose the brand; drawing it from the
/// asset also keeps the diacritics and spacing identical on every screen and density.
class LuqmaLockup extends StatelessWidget {
  const LuqmaLockup({
    super.key,
    this.logo = LuqmaLogo.horizontal,
    this.height,
    this.color,
  });

  /// The app bar form: cream on the burgundy bar, at the documented 21dp mark height.
  const LuqmaLockup.appBar({super.key, this.color})
      : logo = LuqmaLogo.appBar,
        height = 21;

  /// The splash form.
  const LuqmaLockup.splash({super.key, this.height = 220})
      : logo = LuqmaLogo.stacked,
        color = null;

  final LuqmaLogo logo;

  /// Rendered height in logical pixels. Defaults to the size each form is drawn for.
  final double? height;

  /// Recolours the whole lockup. Leave null to keep the asset's own brand colours;
  /// the stacked form carries its own burgundy panel and ignores this.
  final Color? color;

  static const _assets = {
    LuqmaLogo.mark: 'assets/brand/logo_mark.svg',
    LuqmaLogo.markSmall: 'assets/brand/logo_mark_small.svg',
    LuqmaLogo.wordmark: 'assets/brand/logo_wordmark.svg',
    LuqmaLogo.horizontal: 'assets/brand/logo_lockup_horizontal.svg',
    LuqmaLogo.appBar: 'assets/brand/logo_lockup_appbar.svg',
    LuqmaLogo.stacked: 'assets/brand/logo_lockup_stacked.svg',
  };

  static const _defaultHeights = {
    LuqmaLogo.mark: 48.0,
    LuqmaLogo.markSmall: 24.0,
    LuqmaLogo.wordmark: 28.0,
    LuqmaLogo.horizontal: 32.0,
    LuqmaLogo.appBar: 21.0,
    LuqmaLogo.stacked: 220.0,
  };

  @override
  Widget build(BuildContext context) {
    final h = height ?? _defaultHeights[logo]!;
    return Semantics(
      label: 'لقمة',
      image: true,
      excludeSemantics: true,
      child: SvgPicture.asset(
        _assets[logo]!,
        package: 'luqma_core',
        height: h,
        colorFilter: color == null || logo == LuqmaLogo.stacked
            ? null
            : ColorFilter.mode(color!, BlendMode.srcIn),
      ),
    );
  }
}
