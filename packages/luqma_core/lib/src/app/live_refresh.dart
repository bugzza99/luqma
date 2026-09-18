import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_service.dart';
import '../providers/providers.dart';
import 'push.dart';

/// Keeps what the admin changes from needing a restart to be seen.
///
/// The owner reported it as one bug: approve something from AdminApp, and the merchant or
/// the customer has to close the app and open it again before it shows. It was several.
/// Lists that listen to realtime were always fine; what went stale was everything read
/// once — a shop's plan and its benefits, the plans themselves, the category chips, the
/// zones, the shop's own statement — and the claims on the access token, which say who
/// somebody is and are only re-read when the token rotates.
///
/// So this asks again on the two moments something is likely to have changed: the app
/// coming back to the screen, and a notification arriving while it is on it (which is
/// nearly always the server announcing exactly such a change). The shop row itself is live
/// now (`merchantProvider`); this is for the rest.
class LuqmaLiveRefresh extends ConsumerStatefulWidget {
  const LuqmaLiveRefresh({super.key, required this.child, this.minInterval});

  final Widget child;

  /// How soon a second refresh is allowed after the last one. Switching apps twice in
  /// ten seconds is not two reasons to ask the server everything again.
  final Duration? minInterval;

  @override
  ConsumerState<LuqmaLiveRefresh> createState() => _LuqmaLiveRefreshState();
}

class _LuqmaLiveRefreshState extends ConsumerState<LuqmaLiveRefresh>
    with WidgetsBindingObserver {
  StreamSubscription<LuqmaTap>? _messages;
  Timer? _tick;
  DateTime? _last;

  /// While the app is on screen, the one-shot reads are asked again this often. Not every
  /// admin change sends a notification — a new chip, a plan's price, a shop suspended —
  /// and somebody who never leaves the screen would otherwise never see it.
  static const _foregroundEvery = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A message is always worth acting on, however recent the last refresh: it is the
    // server saying *this* just changed.
    _messages = LuqmaPush.received.stream.listen((_) => _refresh(force: true));
    _startTicking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messages?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _startTicking();
    } else if (state == AppLifecycleState.paused) {
      // Nothing is on screen to be stale; a phone in a pocket should not be polling.
      _tick?.cancel();
    }
  }

  void _startTicking() {
    _tick?.cancel();
    // The session is left alone on a tick: claims change rarely, every such change sends
    // a notification, and a token refresh every two minutes is traffic for nothing.
    _tick = Timer.periodic(_foregroundEvery, (_) {
      if (mounted) refreshServerState(ref, session: false);
    });
  }

  void _refresh({bool force = false}) {
    if (!mounted) return;
    final now = DateTime.now();
    final gap = widget.minInterval ?? const Duration(seconds: 20);
    if (!force && _last != null && now.difference(_last!) < gap) return;
    _last = now;
    refreshServerState(ref);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Everything read once that the admin can change from the other side, asked for again.
///
/// Invalidating a provider nobody is listening to costs nothing, so this names them all
/// rather than guessing which screen is open. Never throws: every step either cannot, or
/// returns a `Result` that is dropped on purpose — a refresh that fails leaves the last
/// good values on screen, which is what a failed refresh should do.
void refreshServerState(WidgetRef ref, {bool session = true}) {
  // Who this is. Claims change when an account is approved, attached, promoted or
  // dismissed, and the gates above every screen read them from the token.
  final auth = ref.read(authServiceProvider);
  if (session && auth.state == AuthState.signedIn) unawaited(auth.refreshSession());

  unawaited(ref.read(appConfigProvider.notifier).refresh());

  ref
    ..invalidate(merchantPerksProvider)
    ..invalidate(planAllowanceProvider)
    ..invalidate(pushSlotAvailableProvider)
    ..invalidate(plansProvider)
    ..invalidate(cuisinesProvider)
    ..invalidate(zonesProvider)
    ..invalidate(landmarksProvider)
    ..invalidate(popularItemsProvider)
    ..invalidate(offerItemsProvider)
    ..invalidate(allOfferItemsProvider)
    // Live already, but a subscription cannot hear about a row it may no longer read: a
    // shop the admin suspends vanishes from a customer's view without an event reaching
    // them. Subscribing again asks, and gets the answer — gone — that the screen shows.
    ..invalidate(merchantProvider)
    ..invalidate(merchantSettlementsProvider)
    ..invalidate(commissionPaymentsProvider)
    ..invalidate(settlementSummaryProvider)
    ..invalidate(merchantSalesProvider)
    ..invalidate(courierDaySummaryProvider)
    ..invalidate(myAddressesProvider)
    ..invalidate(adminAttentionProvider);
}
