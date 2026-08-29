import 'dart:async';

import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'alarm.dart';

part 'order_alarm.g.dart';

/// Decides when the new-order sound plays.
///
/// Two failures to avoid, and the second is the expensive one. A sound that stops too
/// early is a merchant who does not hear an order. A sound that will not stop is a
/// merchant who turns notifications off — and then never hears any of them again,
/// including the ones that matter.
///
/// So it rings for orders nobody has dealt with, it stops the moment a human says they
/// have it *or* the order is answered from anywhere else, and it rings again for the
/// next one. Acknowledging order 101 must never swallow the sound for 102.
///
/// The state it exposes is simply whether it is ringing, so a screen can offer to
/// silence it.
@Riverpod(keepAlive: true)
class OrderAlarm extends _$OrderAlarm {
  /// Orders the merchant has already been told about.
  ///
  /// Kept per order id rather than as a single "silenced" flag, because a flag would be
  /// cleared by the next emission of a list that has not changed — Firestore re-emits
  /// for reasons of its own — and the alarm would start again for an order somebody is
  /// already looking at.
  final _acknowledged = <String>{};

  @override
  bool build() {
    final merchantId = ref.watch(staffIdentityProvider).merchantId;
    if (merchantId == null) return false;

    // Later emissions assign `state`; the first one is the value this build returns.
    // Firing the listener immediately would assign `state` before the notifier exists,
    // which Riverpod reports as a circular dependency and is easy to write by accident.
    ref.listen(incomingOrdersProvider(merchantId), (_, next) {
      // An error is not an empty inbox. `next.value ?? const []` treats a dropped
      // connection as "no orders waiting", which stops the alarm — so the one event that
      // should make the merchant *more* suspicious made the phone go quiet instead.
      //
      // On an error the alarm keeps doing whatever it was doing. A false alarm is a
      // merchant checking a screen; a silenced one is an order nobody cooked.
      if (next.hasError) return;
      state = _decide(next.value ?? const []);
    });

    return _decide(ref.read(incomingOrdersProvider(merchantId)).value ?? const []);
  }

  /// Works out whether the sound should be going, starts or stops it, and returns the
  /// answer for whoever is setting state.
  bool _decide(List<Order> waiting) {
    final ids = {for (final o in waiting) o.id};

    // An order that left the list was answered — here, on another phone in the shop, or
    // by the deadline task. Forgetting it keeps this set from growing for the life of
    // the session, and means the sound would ring again if it somehow came back.
    _acknowledged.removeWhere((id) => !ids.contains(id));

    final shouldRing = ids.difference(_acknowledged).isNotEmpty;
    _apply(shouldRing);
    return shouldRing;
  }

  void _apply(bool shouldRing) {
    final alarm = ref.read(alarmProvider);
    // Neither future is awaited — this is called from a listener and from `build`, and
    // neither can wait on a device. But a dropped future that rejects is an *unhandled*
    // asynchronous error, which by default takes down the zone it was raised in; and
    // the one failure worth knowing about in this whole app is the alarm not sounding.
    // So each is caught and named instead.
    final work = shouldRing ? alarm.start() : alarm.stop();
    unawaited(work.catchError((Object error) {
      LuqmaTelemetry.event('alarm_failed', data: {
        'action': shouldRing ? 'start' : 'stop',
        'error': error.toString(),
      });
    }));
  }

  /// The merchant has seen it. Silences the sound for everything waiting right now, and
  /// for nothing that arrives after.
  void acknowledge() {
    final merchantId = ref.read(staffIdentityProvider).merchantId;
    if (merchantId == null) return;

    final waiting = ref.read(incomingOrdersProvider(merchantId)).value ?? const [];
    _acknowledged.addAll(waiting.map((o) => o.id));
    _apply(false);
    state = false;
  }
}
