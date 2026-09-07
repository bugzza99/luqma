import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// A card or tile that answers the finger holding it.
///
/// `Motion.tap` and `Elevations.cardPressed` were both drawn in Phase 0 and then read by
/// nothing: every tappable card in all three apps sat perfectly still under a press and
/// only moved once it was let go and a route pushed. `docs/14` §4 asks for press feedback
/// inside 100ms, and this is the one widget that gives it — a small scale-down that lands
/// well within that, without putting a frame between the tap and [onTap].
///
/// Reduced motion removes the scale rather than running it in zero time. A card that
/// snaps to 0.97 and back is a flicker, and somebody who asked for less motion asked for
/// none of that — so for them the card does not move and [onTap] still fires.
///
/// **Built on [InkWell] with its ripple turned off, not on a bare [GestureDetector].**
/// The first version was the latter, and it silently dropped everything an `InkWell`
/// gives away for free besides the ripple: keyboard focus, Enter and Space activation, a
/// focus ring, and hover. On a phone that reads as nothing missing — until somebody uses
/// Switch Access or an external keyboard, at which point every card in the product has
/// stopped being reachable. `button: true` in the semantics announces a control; it does
/// not make one focusable.
class LuqmaPressable extends StatefulWidget {
  const LuqmaPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.selected,
  });

  final Widget child;
  final VoidCallback onTap;

  /// `true`/`false` when the control is a toggle; null when "selected" does not apply.
  final bool? selected;

  /// How far the card draws back under a press. Small enough to read as "held" rather
  /// than as the card shrinking.
  static const pressedScale = 0.97;

  @override
  State<LuqmaPressable> createState() => _LuqmaPressableState();
}

class _LuqmaPressableState extends State<LuqmaPressable> {
  bool _down = false;
  Timer? _hold;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  /// Holds the pressed state for at least one [Motion.tap] once it starts.
  ///
  /// A quick tap raises and lowers the highlight inside a single frame, so the scale
  /// target changed from 1 to 0.97 and back before anything was ever painted at 0.97 —
  /// the animation had nothing to animate and the card stayed still. The tap that most
  /// needs to feel answered is the fast one, so the release waits for the press to have
  /// been visible.
  void _set(bool down) {
    _hold?.cancel();
    if (down) {
      if (!_down) setState(() => _down = true);
      return;
    }
    _hold = Timer(Motion.tap, () {
      if (mounted && _down) setState(() => _down = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Answered here the way the rest of the product answers it: `Motion.of` collapses the
    // token to zero, and the scale target below is pinned to 1 so nothing moves at all.
    final still = MediaQuery.disableAnimationsOf(context);
    final pressed = _down && !still;

    return Semantics(
      container: true,
      selected: widget.selected,
      child: InkWell(
        onTap: widget.onTap,
        // The scale replaces the ripple rather than joining it: a card that both shrinks
        // and washes with colour is two answers to one press.
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        // Fires for a finger and for a keyboard, which is why the scale hangs off it
        // rather than off raw tap callbacks — activating a focused card with Enter looks
        // the same as pressing it.
        onHighlightChanged: _set,
        child: AnimatedScale(
          scale: pressed ? LuqmaPressable.pressedScale : 1.0,
          duration: Motion.of(context, Motion.tap),
          curve: Motion.enter,
          child: widget.child,
        ),
      ),
    );
  }
}
