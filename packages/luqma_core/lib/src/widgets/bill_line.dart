import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';

/// One line of a bill: what it is on one side, what it costs on the other.
///
/// Shared rather than private because it was about to become the second private copy of
/// itself. The instant checkout has drawn its bill this way since Phase 3; the pre-order
/// reservation grew one when it learned to show a delivery charge, and the new copy set
/// no colours while the old one set two — the same widget already disagreeing with itself
/// on its second day.
///
/// `CLAUDE.md` records what that habit costs here: seventeen private `_Error` copies that
/// had drifted into fifteen different versions, none of them with a way out. It is much
/// cheaper to stop at two.
///
/// [emphasis] is for a discount — money coming off — which is the one line on a bill that
/// is good news and the one that is drawn in `success`.
class LuqmaBillLine extends StatelessWidget {
  const LuqmaBillLine({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final tone = emphasis ? colors.success : colors.textPrimary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style:
                theme.textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
        ),
        const SizedBox(width: Space.sm),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: tone)),
      ],
    );
  }
}
