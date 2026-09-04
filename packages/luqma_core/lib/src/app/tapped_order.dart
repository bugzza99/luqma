import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'push.dart';

/// Hands the order behind a tapped notification to whoever can open it.
///
/// [LuqmaPush] has recorded that order in four places since Phase 4 — the launch
/// details, the foreground tap, the background tap, and the local plugin's own response
/// — and **nothing anywhere read it**. So the alarm rang, the merchant tapped it, and the
/// app came forward on whatever screen it happened to be on, with the order they were
/// told about nowhere in sight. Same shape as the ratings that were collected and never
/// counted: the writer existed, the column existed, the reader did not.
///
/// Wrapped around each app's shell rather than living in one of them, because the three
/// apps disagree about where an order *is* — a tracking screen, an inbox tab, a
/// dashboard — and agree about everything else here.
class LuqmaTappedOrder extends StatefulWidget {
  const LuqmaTappedOrder({super.key, required this.onOpen, required this.child});

  /// Called with the order id, on a frame where navigating is allowed.
  final void Function(String orderId) onOpen;

  final Widget child;

  @override
  State<LuqmaTappedOrder> createState() => _LuqmaTappedOrderState();
}

class _LuqmaTappedOrderState extends State<LuqmaTappedOrder> {
  @override
  void initState() {
    super.initState();
    LuqmaPush.tappedOrder.addListener(_take);
    // The launch case, and the reason this cannot be a listener alone: a notification
    // tapped while the app was dead is already sitting in the notifier before any widget
    // of this app exists, so no listener added here would ever hear it change.
    _take();
  }

  @override
  void dispose() {
    LuqmaPush.tappedOrder.removeListener(_take);
    super.dispose();
  }

  /// Takes the pending order and clears it, rather than reading and remembering.
  ///
  /// Clearing is what makes it happen once: a shell rebuilds on every tab switch, and an
  /// order that reopens itself each time is a screen nobody can get out of. It also
  /// keeps a second notification about the *same* order working — two alerts are two
  /// requests to see it, and a "have I shown this id already" guard would swallow the
  /// second one.
  void _take() {
    final orderId = LuqmaPush.tappedOrder.value;
    if (orderId == null || orderId.isEmpty) return;
    LuqmaPush.tappedOrder.value = null;

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
        if (mounted) widget.onOpen(orderId);
      });
      return;
    }

    widget.onOpen(orderId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
