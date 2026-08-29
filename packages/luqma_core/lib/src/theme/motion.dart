import 'package:flutter/widgets.dart';

/// Motion tokens. One duration reused everywhere is what makes an app feel mechanical,
/// so these are chosen per distance and complexity, not copied.
abstract final class Motion {
  const Motion._();

  /// Press feedback. Must land inside 100ms or the tap feels dead.
  static const tap = Duration(milliseconds: 100);

  /// Small in-place changes: a chip selecting, a badge counting.
  static const quick = Duration(milliseconds: 160);

  /// Bottom sheets and dialogs.
  static const sheet = Duration(milliseconds: 250);

  /// Whole-screen transitions.
  static const page = Duration(milliseconds: 300);

  /// Delay between items in a staggered list, capped at [staggerMax] items —
  /// past that the last row arrives late enough to read as lag.
  static const stagger = Duration(milliseconds: 40);
  static const staggerMax = 6;

  /// One pulse of the merchant's new-order alert. Loops until the order is opened.
  static const alertPulse = Duration(milliseconds: 800);

  /// Splash target. The wordmark fades in over this; the screen is dismissed sooner
  /// if the app is ready before it elapses.
  static const splash = Duration(milliseconds: 1500);

  static const enter = Curves.easeOutCubic;

  /// Exits run faster than entries — a leaving element should not hold attention.
  static const exit = Curves.easeInCubic;

  static const emphasis = Curves.easeInOutCubic;

  /// Returns [Duration.zero] when the platform asks for reduced motion, so callers can
  /// pass a token straight into an animation without branching at every call site.
  static Duration of(BuildContext context, Duration token) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : token;
  }
}
