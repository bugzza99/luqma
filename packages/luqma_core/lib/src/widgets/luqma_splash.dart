import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/motion.dart';
import 'luqma_lockup.dart';

/// The Flutter half of Luqma's single, continuous splash.
///
/// Android 12 and above draw a system splash that cannot be turned off, which is why most
/// apps show two in a row. Ours shows one: the system splash paints the mark on burgundy,
/// and this widget picks it up at the same size in the same place, then completes the
/// lockup by lifting the mark and fading the wordmark in beneath it. The user sees one
/// image assembling itself, not a screen replaced by another screen.
///
/// The alignment that makes this work is [markSize] matching the system drawable's
/// rendered size. The drawable is authored for that in `brand/src/build_android.py`, but
/// the value must still be checked against a real device — Android sizes the splash icon
/// itself, and the exact figure is not knowable from the Flutter side alone.
class LuqmaSplash extends StatefulWidget {
  const LuqmaSplash({
    super.key,
    this.ready,
    this.onFinished,
    this.minimumDuration,
  });

  /// The app's own start-up work. The splash waits for this and for its animation, then
  /// finishes — so a slow start extends it rather than cutting it off mid-fade, and a
  /// fast start never leaves the user waiting on decoration.
  final Future<void>? ready;

  final VoidCallback? onFinished;

  /// How long the assembly takes. Comes from `LuqmaConfig.splashMinMillis`, so the owner
  /// can shorten it once the brand is familiar without shipping a new build. Falls back
  /// to the motion token when nothing is passed.
  final Duration? minimumDuration;

  /// Must match the mark's rendered size in the system splash drawable.
  static const markSize = 132.0;

  @override
  State<LuqmaSplash> createState() => _LuqmaSplashState();
}

class _LuqmaSplashState extends State<LuqmaSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.minimumDuration ?? Motion.splash,
  );

  late final Animation<double> _wordmark = CurvedAnimation(
    parent: _controller,
    // The wordmark starts only after the mark has settled, so the two read as one
    // gesture rather than two things moving at once.
    curve: const Interval(0.45, 1.0, curve: Motion.enter),
  );

  late final Animation<double> _lift = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 0.9, curve: Motion.emphasis),
  );

  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.wait([
      _controller.forward(),
      if (widget.ready != null) widget.ready!,
    ]);
    if (!mounted || _finished) return;
    _finished = true;
    widget.onFinished?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion means the lockup is simply present — no assembly, no delay beyond
    // whatever the app itself needs.
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cream = LuqmaPalette.cream;
    const gap = 26.0;
    const wordmarkHeight = 46.0;
    final lift = (wordmarkHeight + gap) / 2;

    return ColoredBox(
      color: LuqmaPalette.burgundy,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(0, lift * (1 - _lift.value)),
                  child: const LuqmaLockup(
                    logo: LuqmaLogo.markSmall,
                    height: LuqmaSplash.markSize,
                    color: cream,
                  ),
                ),
                SizedBox(height: gap * _lift.value),
                Opacity(
                  opacity: _wordmark.value,
                  child: SizedBox(
                    height: wordmarkHeight * _lift.value,
                    child: const OverflowBox(
                      maxHeight: wordmarkHeight,
                      alignment: Alignment.topCenter,
                      child: LuqmaLockup(
                        logo: LuqmaLogo.wordmark,
                        height: wordmarkHeight,
                        color: cream,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
