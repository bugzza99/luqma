import 'dart:async';

import 'package:flutter/widgets.dart';

import 'courier_write_queue.dart';

/// Sends what the courier queued, without being asked.
///
/// The queue was built to be driven — its own `flush` says "this runs from a connectivity
/// listener, and a courier keeps working while it does" — and nothing ever drove it. The
/// only call in the whole product was a retry button on the courier's screen, so a rider
/// could collect cash at a door, tap delivered with no signal, walk back into coverage,
/// and leave the order unsettled for as long as nobody happened to press that button.
///
/// The screen meanwhile says «هيتبعت أول ما النت يرجع». This is what makes that sentence
/// true.
///
/// **No connectivity package.** Adding one to learn a fact the next attempt establishes
/// anyway is a dependency, a permission on some platforms, and a second thing that can be
/// wrong. A queued write costs one refused request to discover the network is still down;
/// what matters is that something keeps asking. So: on resume, and on a backoff while
/// anything is waiting.
class CourierQueueDrain with WidgetsBindingObserver {
  CourierQueueDrain(this._queue);

  final CourierWriteQueue _queue;

  /// Starts short so an ordinary blackspot clears in seconds, and grows so a rider parked
  /// out of coverage for an hour is not spending their battery on it.
  static const firstDelay = Duration(seconds: 10);
  static const maxDelay = Duration(minutes: 5);

  Timer? _timer;
  Duration _delay = firstDelay;
  bool _draining = false;
  bool _started = false;

  /// Begins watching. Safe to call twice; the second is a no-op.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _observe();
    // Subscribed rather than polled: a tap made offline should start the clock, not wait
    // for whatever interval happens to be running.
    _queue.changes.listen((_) => _schedule(reset: true));
    await drain();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    _timer?.cancel();
    _timer = null;
  }

  /// Whether another attempt is armed.
  ///
  /// Exposed because "stops asking once there is nothing to send" is a real promise — a
  /// drain that keeps waking on an empty queue is a battery a rider notices — and a
  /// promise with no way to check it is not one.
  bool get isWaiting => _timer?.isActive ?? false;

  bool _observing = false;

  /// The lifecycle hook is a nicety; the retry below is the guarantee.
  ///
  /// `WidgetsBinding.instance` throws when no binding has been initialised, and the queue
  /// is built by a provider an ordinary Dart test is entitled to construct without one —
  /// which is exactly what happened the first time this was wired in. Resume detection is
  /// worth having and is not worth making the queue unbuildable for.
  void _observe() {
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      // No binding: on a phone there always is one, so this is a test, and the timer
      // still sends everything that gets queued.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is the strongest signal available without asking the
    // platform anything: it usually means the phone is in the rider's hand, which is
    // usually where the signal came back.
    if (state == AppLifecycleState.resumed) {
      _delay = firstDelay;
      unawaited(drain());
    }
  }

  /// Sends whatever is waiting. One at a time.
  ///
  /// A second drain overlapping the first would replay the same write twice — the queue
  /// reconciles rather than replaces, but two passes over one entry is two requests for
  /// one tap, and these are requests that move money.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      await _queue.flush();
    } catch (_) {
      // Never allowed to escape. This runs unawaited from a lifecycle callback and from a
      // timer, and `CLAUDE.md` records what an unhandled async error costs in these
      // builds: Sentry reports it through `PlatformDispatcher.onError` as **fatal**, which
      // is how three release APKs died on launch. A courier's app must not close because
      // a retry failed — the whole point of the queue is that failing is survivable.
    } finally {
      _draining = false;
    }
    _schedule();
  }

  /// Arms the next attempt, or stands down when there is nothing left to send.
  void _schedule({bool reset = false}) {
    _timer?.cancel();
    _timer = null;
    if (reset) _delay = firstDelay;

    if (_queue.pending.isEmpty) {
      // Nothing waiting: no timer at all, rather than one that wakes to find an empty
      // queue for the rest of the shift.
      _delay = firstDelay;
      return;
    }

    _timer = Timer(_delay, () => unawaited(drain()));
    final next = _delay * 2;
    _delay = next > maxDelay ? maxDelay : next;
  }
}
