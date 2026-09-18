import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'push.dart';

/// Hands the payload behind a tapped notification to whoever can open it.
///
/// [LuqmaPush] records the tap in four places — the launch details, the foreground tap,
/// the background tap, and the local plugin's own response.
///
/// Wrapped around each app's shell rather than living in one of them, because the three
/// apps disagree about where each kind of notification belongs — a tracking screen,
/// an inbox tab, a dashboard, etc. — and agree about everything else here.
class LuqmaTappedNotification extends StatefulWidget {
  const LuqmaTappedNotification({
    super.key,
    required this.onOpen,
    required this.child,
  });

  /// Called with the tapped notification payload, on a frame where navigating is allowed.
  final void Function(LuqmaTap tap) onOpen;

  final Widget child;

  @override
  State<LuqmaTappedNotification> createState() => _LuqmaTappedNotificationState();
}

class _LuqmaTappedNotificationState extends State<LuqmaTappedNotification> {
  @override
  void initState() {
    super.initState();
    LuqmaPush.tapped.addListener(_take);
    // The launch case, and the reason this cannot be a listener alone: a notification
    // tapped while the app was dead is already sitting in the notifier before any widget
    // of this app exists, so no listener added here would ever hear it change.
    _take();
  }

  @override
  void dispose() {
    LuqmaPush.tapped.removeListener(_take);
    super.dispose();
  }

  /// Takes the pending tap and clears it, rather than reading and remembering.
  ///
  /// Clearing is what makes it happen once: a shell rebuilds on every tab switch, and a
  /// destination that reopens itself each time is a screen nobody can get out of. It also
  /// keeps a second notification about the *same* destination working — two alerts are two
  /// requests to see it, and a "have I shown this already" guard would swallow the
  /// second one.
  void _take() {
    final tap = LuqmaPush.tapped.value;
    if (tap == null) return;
    LuqmaPush.tapped.value = null;

    // Which of the two ways out depends on when the tap arrived, and getting it wrong
    // fails silently in one direction and loudly in the other.
    //
    // A tap that lands while a frame is being built — `initState` on the launch path is
    // exactly that — must not navigate now: pushing a route during a build is an error.
    // A tap that lands between frames, which is every tap while the app is running, has
    // nothing to wait for, and `addPostFrameCallback` from an idle phase does not
    // schedule a frame of its own — so deferring it unconditionally means it is never
    // called at all, which is the same do-nothing behaviour this whole widget exists to
    // fix.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onOpen(tap);
      });
      return;
    }

    widget.onOpen(tap);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
