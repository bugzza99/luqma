import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';

/// Why a line of notice is on the screen.
///
/// Named rather than coloured, because the screen is the wrong place to decide what red
/// means. A caller says "this is a problem" or "this is worth knowing", and the mapping
/// to a colour lives in one file — which is the whole reason this product has no literal
/// colour in any screen.
enum NoticeTone {
  /// Something is stopping the person: the shop is shut, the address is out of range,
  /// the order was refused.
  problem,

  /// Something worth reading that is nobody's fault — how much more to reach the
  /// minimum, when a meal can be collected.
  information,
}

/// One line under a control, saying why it is the way it is.
///
/// Small, and everywhere it matters: the basket saying the shop is closed, checkout
/// saying the address is outside the zone, the pre-order screen saying the kitchen does
/// not deliver there. It was a private `_Notice` copied into three screens with eight
/// call sites, each passing a raw colour.
class LuqmaNotice extends StatelessWidget {
  const LuqmaNotice({
    super.key,
    required this.icon,
    required this.text,
    this.tone = NoticeTone.problem,
  });

  final IconData icon;
  final String text;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final colour = switch (tone) {
      NoticeTone.problem => colors.danger,
      NoticeTone.information => colors.textSecondary,
    };

    return Row(
      children: [
        Icon(icon, size: Sizes.iconSm, color: colour),
        const SizedBox(width: Space.sm),
        // `Expanded`, because these sentences are full Arabic sentences and the row is
        // as wide as the phone. Without it a long one overflows rather than wrapping.
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}
