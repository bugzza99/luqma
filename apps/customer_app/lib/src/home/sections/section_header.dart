import 'package:flutter/material.dart';
import 'package:luqma_core/luqma_core.dart';

/// One header treatment for every section.
///
/// Shared because the home screen is assembled in an order the app does not control: if
/// each section styled its own heading, a reordering done in AdminApp would show up as a
/// ragged screen rather than a rearranged one.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, Sizes.minTarget),
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                foregroundColor: theme.luqma.price,
                textStyle: LuqmaType.caption,
              ),
              child: const Text('شوف الكل'),
            ),
        ],
      ),
    );
  }
}
