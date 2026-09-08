import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/motion.dart';
import '../theme/dimens.dart';
import 'pressable.dart';

/// One filter pill.
///
/// Shared because it was written twice: the home's cuisine circles and the merchant
/// screen's menu sections drew the same pill from two private `_Chip` classes, down to a
/// reworded copy of the comment explaining the colour. This repository has already paid
/// for that pattern once — seventeen private `_Error` widgets that had drifted into
/// fifteen different versions, none of them with a way out — and a chip is the same shape
/// of thing: small, obvious, and about to be needed on a third screen.
///
/// Selecting animates the fill and the ink rather than rebuilding into place.
/// [Motion.of] drops the duration to zero under reduced motion, so for somebody who asked
/// for less movement the change simply appears.
class LuqmaChip extends StatelessWidget {
  const LuqmaChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dashed = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final duration = Motion.of(context, Motion.quick);

    return LuqmaPressable(
      onTap: onTap,
      selected: selected,
      child: ConstrainedBox(
        // The pill is shorter than a finger, and the constraint lives here rather than on
        // whatever lays it out. In the home's chip row the row was already tall enough,
        // which made a 48dp target a property of the parent — true by coincidence, and
        // silently false the first time the chip was put in a wrap instead.
        constraints: const BoxConstraints(
          minHeight: Sizes.minTarget,
          minWidth: Sizes.minTarget,
        ),
        child: Center(
          widthFactor: 1,
          child: CustomPaint(
            foregroundPainter: dashed && !selected
                ? _DashedOutline(colors.border) : null,
            child: AnimatedContainer(
              duration: duration,
              curve: Motion.emphasis,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                // Burgundy, not the accent. Orange is reserved for prices, offers and
                // ratings — the moment it also means "selected" it stops meaning value
                // anywhere, and every price on every screen loses its pull.
                color: selected ? colors.brand : colors.card,
                borderRadius: Radii.pillAll,
                border: Border.all(
                  color: dashed && !selected ? Colors.transparent
                      : selected ? colors.brand : colors.border,
                ),
              ),
              child: AnimatedDefaultTextStyle(
                duration: duration,
                curve: Motion.emphasis,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: selected ? colors.onBrand : colors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
                child: Text(label, maxLines: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedOutline extends CustomPainter {
  const _DashedOutline(this.color);

  final Color color;
  static const _stroke = 1.0;
  static const _dash = Space.xs;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(Radii.pillAll.toRRect(
      (Offset.zero & size).deflate(_stroke / 2),
    ));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    for (final metric in path.computeMetrics()) {
      for (double start = 0; start < metric.length; start += _dash * 2) {
        canvas.drawPath(metric.extractPath(start, start + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) => color != oldDelegate.color;
}
