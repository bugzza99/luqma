import 'package:flutter/material.dart';

import 'motion.dart';

/// How every screen in the product arrives.
///
/// `docs/14` §4 publishes one answer — 300ms, easeOutCubic — and `Motion.page` has held
/// that number since Phase 0 with nothing reading it. Every push in all three apps ran on
/// whatever Material's platform default happened to be instead, which on Android is a
/// slower vertical fade that has nothing to do with the rest of the design system.
///
/// Set on the theme rather than passed per route, because a transition somebody has to
/// remember to ask for is one that will be forgotten on the twenty-sixth screen — and a
/// product where most screens agree and a few do not feels worse than one where none do.
class LuqmaPageTransitions extends PageTransitionsBuilder {
  const LuqmaPageTransitions();

  @override
  Duration get transitionDuration {
    // Read off the binding rather than a `MediaQuery`, because a route's duration is
    // asked for before there is a `BuildContext` to ask with — and skipping the
    // *painting* while still holding the screen for 300ms would leave somebody who asked
    // for reduced motion staring at a frozen screen, which is worse than the slide.
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return features.disableAnimations ? Duration.zero : Motion.page;
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Reduced motion is on for people who get motion sick and for people using a screen
    // reader. A screen that slides anyway is the one setting they asked us to respect —
    // and this is the single place in the product that decision has to be made.
    if (MediaQuery.disableAnimationsOf(context)) return child;

    // A short slide from the trailing edge under a fade. Directional rather than a plain
    // fade because the app is RTL and the direction is what says "forward" — and
    // `AlignmentDirectional`-aware, so it comes from the correct side in Arabic without
    // a second code path.
    final slide = Tween<Offset>(
      begin: const Offset(0.06, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Motion.enter));

    return SlideTransition(
      position: slide,
      textDirection: Directionality.of(context),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Motion.enter),
        child: child,
      ),
    );
  }
}

/// The same builder for every platform this ships on.
///
/// Android first, iOS and web later from the same code — so the transition is the
/// product's, not the platform's, and a reviewer opening the web build sees the app
/// rather than Chrome's idea of it.
const luqmaPageTransitionsTheme = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: LuqmaPageTransitions(),
    TargetPlatform.iOS: LuqmaPageTransitions(),
    TargetPlatform.fuchsia: LuqmaPageTransitions(),
    TargetPlatform.linux: LuqmaPageTransitions(),
    TargetPlatform.macOS: LuqmaPageTransitions(),
    TargetPlatform.windows: LuqmaPageTransitions(),
  },
);
