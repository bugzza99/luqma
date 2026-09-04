import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// A phone ringing, in whichever of the three apps is holding it.
///
/// It began as the merchant's alarm — the one notification this business genuinely
/// depends on, since everything else degrades when it fails and that one fails as an
/// order nobody cooked. Nothing about the transport was ever merchant-specific though:
/// the channel, the token registration and the pruning are the same three problems for a
/// customer being told their food left the kitchen and for an admin being told nobody
/// answered an order.
///
/// So it lives here, and each app supplies the one thing that genuinely differs — which
/// Android channel its alerts belong on, created natively in that app's MainActivity
/// before Flutter starts.
///
/// This is the only file in the workspace that knows Firebase exists. The backend is
/// Supabase; Messaging is the single Google product left, because Supabase has no push
/// transport of its own.
///
/// Everything here is inert without `google-services.json`: [start] returns quietly, so a
/// developer without the file gets an app that runs rather than an app that crashes on
/// launch.
/// Draws the alert when a message arrives and the app is not in the foreground.
///
/// Runs in its own isolate with none of the app around it — no providers, no session, no
/// navigator. It may do exactly one thing: render the notification. Anything it needed
/// from the app would not be there.
///
/// `vm:entry-point` keeps it from being tree-shaken out of a release build, where it is
/// only ever reached from native code.
@pragma('vm:entry-point')
Future<void> luqmaBackgroundMessage(RemoteMessage message) async {
  // Android already drew it.
  //
  // Every message carries a `notification` block now, so the system renders the alert
  // itself on the channel the payload names — which is what makes one arrive at all when
  // the app has been swiped away. This isolate still wakes, and if it drew as well the
  // merchant would get the same order twice, with the alarm playing over itself.
  //
  // The guard is on the message rather than a flag, so a payload that genuinely carries
  // no notification — one sent by hand, or an older row — still gets rendered here.
  if (message.notification != null) return;

  await Firebase.initializeApp();
  await LuqmaPush.render(message);
}

/// Whether this phone will show what the server sends.
///
/// Four states rather than a bool, because "not asked yet" and "said no" want opposite
/// things from a screen: the first wants an explanation and then the system dialog, and
/// the second wants telling that alerts are off, since Android will not show that dialog
/// a second time.
enum LuqmaPushPermission {
  /// Alerts will be shown.
  granted,

  /// Asked, and refused. The system dialog will not appear again — only Settings can
  /// change this — so a button that merely asks again is a button that does nothing.
  denied,

  /// Never asked. Android 13 and up starts here; older versions never do.
  notDetermined,

  /// No Firebase in this build, so there is nothing to ask about. A developer's machine
  /// and CI are both here, and neither should be shown a warning about notifications.
  unavailable,
}

abstract final class LuqmaPush {
  const LuqmaPush._();

  /// The channel created natively in MainActivity, at max importance with the alarm
  /// sound. Named here so the payload and the channel cannot drift apart.
  ///
  /// Not every app has it. A customer's phone is told their food is on the way, and
  /// waking somebody with a looping alarm to say so is how they turn the app's
  /// notifications off — taking the two messages that matter with them. The server picks
  /// the channel per message; this is the fallback when it names none.
  static const ordersChannel = 'orders_critical';

  /// The ordinary channel: a sound, once, and no bypassing Do Not Disturb.
  static const quietChannel = 'orders';

  /// The offers, kept apart from both of the above on purpose.
  ///
  /// A customer tired of the advertising reaches for the phone's own notification
  /// settings long before they go looking through حسابي, and if offers shared a channel
  /// with order updates, silencing the first would silence the second — somebody would
  /// stop being told where their food is because they turned off an ad.
  static const marketingChannel = 'marketing';

  static final _local = FlutterLocalNotificationsPlugin();

  /// The in-flight (or finished) [start], so [token] can wait for it.
  ///
  /// `start()` is deliberately not awaited by any `main` — it asks for the notification
  /// permission, and awaiting a system dialog before `runApp` holds the first frame on a
  /// white screen until somebody answers it. That leaves a race: the session can restore
  /// and ask for a token before Firebase has finished initialising, `getToken()` throws,
  /// and registration gives up **silently and for the whole session**.
  ///
  /// The merchant app never showed it because a merchant signs in by hand, seconds after
  /// launch. A customer or an admin with a restored session asks within milliseconds.
  static Future<bool>? _starting;

  /// Fires when Android reissues this device's token.
  ///
  /// It does so after a reinstall, a restore, a clear-data, or on its own after a long
  /// silence — and nothing listened, so a phone whose token changed mid-session went
  /// quiet with the old one still on the account and nothing anywhere saying so.
  ///
  /// `async*`, and the `await` is the entire point. This was an expression-bodied getter
  /// over `FirebaseMessaging.instance.onTokenRefresh`, and `main` reads it as an argument
  /// in its first few lines — before the `Firebase.initializeApp()` inside [start], which
  /// nothing awaits. So it threw `[core/no-app]` uncaught, inside `main`, and three
  /// release APKs died on launch: not a feature that degraded, an app that would not
  /// open. The fix sits next to `_starting`, which was added for exactly this reason and
  /// which this getter then failed to use.
  ///
  /// A generator body runs on the first listen rather than on the read, so nothing here
  /// touches Firebase until somebody is actually waiting for tokens — and even then, not
  /// until [start] has answered.
  static Stream<String> get tokenRefreshes async* {
    // False means this build has no Firebase at all, which is an ordinary state for a
    // developer's machine and for CI. An empty stream is the honest answer: there are no
    // tokens to refresh, and there is nothing wrong.
    if (!await start()) return;
    yield* FirebaseMessaging.instance.onTokenRefresh;
  }

  /// The order behind the notification somebody just tapped, or null.
  ///
  /// A `ValueNotifier` rather than a route: the tap can arrive while the app is starting,
  /// from a terminated state, or in the background isolate, and none of those has a
  /// navigator to push onto. The shell watches this and opens the order when it can.
  static final tappedOrder = ValueNotifier<String?>(null);

  /// Starts Messaging and asks for permission.
  ///
  /// It deliberately does **not** register a token. The ownership RPC takes its uid from
  /// the signed-in session, and at launch nobody is signed in — somebody who installs the
  /// app, opens it and then signs in would have had registration run and be refused,
  /// silently. `keepPushTokenRegistered` follows the session instead.
  ///
  /// Returns false when Firebase is not configured in this build, which is a normal
  /// state and not an error — the rest of the app works without it.
  static Future<bool> start() {
    final started = _starting;
    if (started != null) return started;
    return _starting = _start();
  }

  static Future<bool> _start() async {
    // One try around the whole body, and it is not defensive padding.
    //
    // No `main` awaits this — `unawaited(LuqmaPush.start())` — and Sentry installs a
    // `PlatformDispatcher.onError` that reports unhandled async errors as **fatal**. So
    // any throw escaping here is not a feature that failed to start, it is a crash
    // reported against an app the customer is looking at.
    //
    // Only `Firebase.initializeApp()` used to be guarded, and everything after it —
    // asking for the notification permission, initialising the local plugin, reading the
    // launch details — was outside. Every one of those is a platform channel on an OEM
    // Android build, which is the least predictable code this app runs.
    try {
      await Firebase.initializeApp();
    } catch (error) {
      // No google-services.json, or a build that never registered. Said once, loudly
      // enough to find in a log, and then out of the way. This is a normal state for a
      // developer's machine and for any app whose config has not been added yet — the
      // rest of the app works without it.
      debugPrint('Push is off: Firebase is not configured in this build ($error)');
      return false;
    }

    try {
      return await _wire();
    } catch (error, stackTrace) {
      // Distinct from the message above on purpose: that one is an expected state, this
      // one is something going wrong on a phone and is worth finding in a log.
      debugPrint('Push is off: setting it up failed ($error)\n$stackTrace');
      return false;
    }
  }

  /// Everything after Firebase is up. Separated so the guard above covers all of it
  /// rather than whichever lines somebody remembers to keep inside a `try`.
  static Future<bool> _wire() async {
    // Deliberately does **not** ask for the permission.
    //
    // It used to, right here, in the first seconds of the first launch — before anybody
    // had been told what the alerts were for, and while the app was still drawing its
    // splash. Android shows that dialog once and remembers a refusal permanently, so an
    // unexplained prompt spends the only chance the app gets; and nothing read the
    // answer, so a merchant who tapped "Don't allow" got a phone that never rang again
    // with nothing anywhere saying why.
    //
    // [requestPermission] is called from a screen now, next to the sentence explaining
    // what it buys, and [LuqmaNotificationBanner] is what says so when it is off.
    await _initLocal();

    // A notification tapped while the app was dead is waiting here at launch. Without
    // this somebody taps the alert, the app opens on whatever it opened on last, and the
    // order they were told about is not on the screen.
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      tappedOrder.value = launch!.notificationResponse?.payload;
    }

    // The foreground. Android never draws a `notification` block itself while the app is
    // on screen, so this is the one case where the app has to — and it is also the case
    // where it can do better than the system, because it knows which screen is open.
    FirebaseMessaging.onMessage.listen(_show);

    // Still registered, and it is the *tap* this earns rather than the drawing.
    // `getInitialMessage` and this handler are how the app learns which order somebody
    // tapped; the alert itself is Android's now.
    FirebaseMessaging.onBackgroundMessage(luqmaBackgroundMessage);

    // A notification tapped while the app was in the background, drawn by Android rather
    // than by us — so it never went through `flutter_local_notifications` and its launch
    // details know nothing about it. Without this the merchant taps the alarm, the app
    // comes forward, and the order they were told about is not on screen.
    FirebaseMessaging.onMessageOpenedApp.listen(_openedFrom);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _openedFrom(initial);

    return true;
  }

  /// This device's token, or null when Firebase is not configured here.
  ///
  /// Asked for on every sign-in rather than cached: Android reissues it after a
  /// reinstall, a restore, or a long silence, and a stale one is a phone that has gone
  /// quiet with nothing anywhere saying so.
  static Future<String?> token() async {
    try {
      // Waits for [start] rather than racing it. Without this the first ask can land
      // before `Firebase.initializeApp` has returned, and the exception is swallowed
      // below into a null that reads exactly like "this build has no Firebase".
      if (await (_starting ?? Future.value(true)) == false) return null;
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  /// What this phone has already decided, without asking it anything.
  ///
  /// Reading is not asking: `getNotificationSettings` never shows a dialog, so a screen
  /// can use this to decide whether to explain first, warn, or say nothing at all.
  static Future<LuqmaPushPermission> permission() =>
      _settings((m) => m.getNotificationSettings());

  /// Asks, and answers what was decided.
  ///
  /// Call this **after** somebody has been told what the alerts are for. Android shows
  /// its dialog once and remembers a refusal for good, so an unexplained prompt in the
  /// first seconds of the first launch spends the only chance this app gets — and for a
  /// merchant, refusing it means never hearing that an order arrived.
  static Future<LuqmaPushPermission> requestPermission() => _settings(
        (m) => m.requestPermission(alert: true, sound: true, badge: true),
      );

  static Future<LuqmaPushPermission> _settings(
    Future<NotificationSettings> Function(FirebaseMessaging) ask,
  ) async {
    try {
      if (!await start()) return LuqmaPushPermission.unavailable;
      return switch ((await ask(FirebaseMessaging.instance)).authorizationStatus) {
        // Provisional is iOS delivering quietly without having asked. Alerts arrive, so
        // as far as every screen here is concerned it is granted.
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional =>
          LuqmaPushPermission.granted,
        AuthorizationStatus.denied => LuqmaPushPermission.denied,
        AuthorizationStatus.notDetermined => LuqmaPushPermission.notDetermined,
      };
    } catch (error) {
      // Same rule as everything else in this file: a platform channel on an OEM Android
      // build is the least predictable code the app runs, and a screen asking whether
      // notifications are on must not be able to crash on the answer.
      debugPrint('Could not read the notification permission ($error)');
      return LuqmaPushPermission.unavailable;
    }
  }

  /// Records which order a tapped notification was about.
  static void _openedFrom(RemoteMessage message) {
    final id = message.data['orderId'];
    if (id is String && id.isNotEmpty) tappedOrder.value = id;
  }

  /// Sets the plugin up. Safe to call twice, and called again in the background isolate,
  /// which starts with nothing configured.
  static Future<void> _initLocal() async {
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) =>
          tappedOrder.value = response.payload,
    );
  }

  /// Draws the alert. Public because the background isolate has to reach it.
  static Future<void> render(RemoteMessage message) async {
    await _initLocal();
    await _show(message);
  }

  static Future<void> _show(RemoteMessage message) async {
    final data = message.data;
    final channel = data['channel'] ?? ordersChannel;
    final alarm = channel == ordersChannel;
    // An offer must not arrive with the weight of an order. The channel already decides
    // this for anything Android draws itself; this is the one path where the app draws
    // it, and matching them is what stops the same message looking urgent in the
    // foreground and quiet everywhere else.
    final marketing = channel == marketingChannel;

    await _local.show(
      message.hashCode,
      data['title'] ?? 'لقمة',
      data['body'] ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          switch (channel) {
            ordersChannel => 'أوردرات',
            marketingChannel => 'عروض وخصومات',
            _ => 'تنبيهات',
          },
          importance: marketing ? Importance.low : Importance.max,
          priority: marketing ? Priority.low : Priority.high,
          // The channel already carries the sound and the vibration; setting them here
          // as well is how two definitions start disagreeing.
          //
          // The full-screen intent and the call category are the alarm's, and only the
          // alarm's: they take over the lock screen, which is right for a kitchen that
          // has to answer in ninety seconds and wrong for telling a customer their food
          // has left the shop.
          category: alarm
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.status,
          fullScreenIntent: alarm,
        ),
      ),
      payload: data['orderId'],
    );
  }
}
