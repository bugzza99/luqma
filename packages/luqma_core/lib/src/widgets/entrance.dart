import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// A list item arriving: a short fade and a small lift, staggered by position.
///
/// `docs/14` §4 has asked for 40ms per item capped at six since Phase 0, and
/// `Motion.stagger` / `Motion.staggerMax` have held those numbers with nothing reading
/// them — every list in the product appeared all at once, fully formed.
///
/// The cap is the part worth stating. Without it a merchant's twentieth menu item waits
/// 800ms before it appears, which stops reading as an entrance and starts reading as the
/// app being slow. Past the sixth row everything shares the last delay and arrives
/// together, which is what a person perceives as "the list is here" anyway.
///
/// Runs once, on first build. It is an entrance, not a state: a row that re-animated
/// every time its data changed would flicker on every price edit.
class LuqmaEntrance extends StatefulWidget {
  const LuqmaEntrance({
    super.key,
    required this.index,
    required this.child,
  });

  /// Position in the list. Anything at or past [Motion.staggerMax] shares the last delay.
  final int index;

  final Widget child;

  @override
  State<LuqmaEntrance> createState() => _LuqmaEntranceState();
}

class _LuqmaEntranceState extends State<LuqmaEntrance>
    with SingleTickerProviderStateMixin {
  /// The row's own delay, in steps. Past the cap every row shares the last one.
  late final int _step = widget.index.clamp(0, Motion.staggerMax);

  late final Duration _delay = Motion.stagger * _step;

  /// The delay is part of the controller's own run rather than a `Future.delayed` before
  /// it. One clock per row instead of a timer and a clock: nothing to cancel when the
  /// list is scrolled away from mid-entrance, and the row's progress is a pure function
  /// of elapsed time, which is what makes it testable by pumping.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _delay + Motion.quick,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    // Nothing happens until this row's turn; the fade then runs over what is left.
    curve: Interval(
      _delay.inMicroseconds / (_delay + Motion.quick).inMicroseconds,
      1,
      curve: Motion.enter,
    ),
  );

  late final Animation<Offset> _lift = Tween<Offset>(
    // A small lift rather than a slide across: the row is settling into place, not
    // travelling from somewhere else.
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(_fade);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _lift, child: widget.child),
    );
  }
}
