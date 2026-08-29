import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';

/// What a screen shows when there is nothing to show yet.
///
/// One widget, shared by all three apps, and it exists for the reason [LuqmaErrorView]
/// does: it replaced twelve private `_Empty` copies that had drifted apart. Seven drew an
/// icon and five did not; eleven used one padding and the twelfth another; the text
/// alignment varied. "No orders yet" and "no photos yet" are the same moment in a
/// person's day and looked like different products.
///
/// The drift is the small half. The larger one is that nothing could *change*: an empty
/// basket that wants to say "browse the shops" needed twelve files edited to keep the
/// screens looking alike, so nobody did it, and every empty screen in the product stayed
/// a dead end. [action] is here from the first line for that reason.
///
/// Emptiness is not failure and does not read like it. There is no icon by default and
/// nothing is coloured for danger — a new merchant with no orders has done nothing wrong.
class LuqmaEmptyView extends StatelessWidget {
  const LuqmaEmptyView({
    super.key,
    this.icon,
    this.title,
    this.message,
    this.action,
  }) : assert(title != null || message != null,
            'an empty state with no words is an empty screen');

  /// Drawn above the words when there is one. Half the screens have no icon and read
  /// perfectly well; a picture is worth adding when it says something the sentence
  /// cannot.
  final IconData? icon;

  /// The heading — what is missing, in a few words.
  final String? title;

  /// The explanation under it, when the heading leaves a question. Used alone on screens
  /// where one sentence is the whole story.
  final String? message;

  /// The way out. Usually a button that starts the thing there is none of yet.
  ///
  /// Nothing is drawn when it is null, on the same rule as the error view: a control that
  /// does nothing is worse than no control.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: Sizes.emptyIcon, color: colors.textSecondary),
              const SizedBox(height: Space.lg),
            ],
            if (title != null)
              Text(
                title!,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
            if (title != null && message != null) const SizedBox(height: Space.sm),
            if (message != null)
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            if (action != null) ...[
              const SizedBox(height: Space.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
