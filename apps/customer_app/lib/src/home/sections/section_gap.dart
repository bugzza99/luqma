import 'package:flutter/material.dart';
import 'package:luqma_core/luqma_core.dart';

/// The space beneath a home section, carried by the section rather than by the home.
///
/// It used to be a `SizedBox` between the children of the home's `Column`, which drew it
/// whether or not the section above it had rendered anything. Every section here can come
/// back empty — no cuisines yet, no promotion running, no meals cooking today — and each
/// one answers that by returning `SizedBox.shrink()`, which is the right answer. But the
/// gap it was supposed to be followed by stayed, so on a young city three absent sections
/// stacked their gaps into a void under the search box that reads as a screen that failed
/// to load rather than a city with nothing in it yet.
///
/// Wrapping the *content* means the space and the thing it separates are one widget: no
/// section, no gap.
class SectionGap extends StatelessWidget {
  const SectionGap({super.key, required this.child});

  final Widget child;

  /// Matches the rhythm `docs/14` sets between bands on a scrolling page.
  static const height = Space.xl - 4;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: height),
      child: child,
    );
  }
}
