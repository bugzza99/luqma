import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/promotion_palette.dart';

/// Picking the ground the words sit on.
///
/// Eight swatches and no custom colour. A merchant with a colour wheel picks the one from
/// their sign, which is usually pale, and writes on it in a colour they cannot choose —
/// the ink comes from [PromotionPalette.inkOn] — so a free picker would mostly produce
/// banners that are correct, unreadable, and nobody's fault.
class BannerColorPicker extends StatelessWidget {
  const BannerColorPicker({
    super.key,
    required this.selected,
    required this.onPicked,
  });

  /// The chosen hex, or null for the brand gradient.
  final String? selected;

  final ValueChanged<String?> onPicked;

  static const gradientKey = Key('banner.color.gradient');
  static Key swatchKey(String hex) => Key('banner.color.$hex');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        // The default, and it has to be pickable rather than only reachable by never
        // having touched anything: somebody who tried three colours needs a way back.
        _Swatch(
          key: gradientKey,
          selected: selected == null,
          onTap: () => onPicked(null),
          label: 'التدرج',
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [colors.brand, colors.brandPressed],
          ),
        ),
        for (final hex in PromotionPalette.swatches)
          _Swatch(
            key: swatchKey(hex),
            selected: selected == hex,
            onTap: () => onPicked(hex),
            label: hex,
            color: PromotionPalette.parse(hex),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.selected,
    required this.onTap,
    required this.label,
    this.color,
    this.gradient,
  });

  final bool selected;
  final VoidCallback onTap;
  final String label;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Sizes.minTarget),
        child: Container(
          width: Sizes.minTarget,
          height: Sizes.minTarget,
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            shape: BoxShape.circle,
            // The chosen one is ringed rather than ticked: a tick has to be drawn in a
            // colour, and the one colour guaranteed to read on every swatch here is the
            // background the swatches sit on.
            border: Border.all(
              color: selected ? colors.textPrimary : colors.hairline,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
