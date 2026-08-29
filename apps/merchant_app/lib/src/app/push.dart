import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The merchant's phone ringing when an order arrives.
///
/// The one notification this business genuinely depends on. Everything else in the
/// product degrades when it fails; this one fails as an order nobody cooked.
///
/// This is the only file in the app that knows Firebase exists. The backend is Supabase —
/// Messaging is the single Google product left, because Supabase has no push transport,
/// and the Android channel and the looping alarm have been sitting here since Phase 4
/// waiting for something to send them a message.
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
  await Firebase.initializeApp();
  await LuqmaPush.render(message);
}

abstract final class LuqmaPush {
  const LuqmaPush._();

  /// The channel created natively in MainActivity, at max importance with the alarm
  /// sound. Named here so the payload and the channel cannot drift apart.
  static const ordersChannel = 'orders_critical';

  static final _local = FlutterLocalNotificationsPlugin();

  /// The order behind the notification somebody just tapped, or null.
  ///
  /// A `ValueNotifier` rather than a route: the tap can arrive while the app is starting,
  /// from a terminated state, or in the background isolate, and none of those has a
  /// navigator to push onto. The shell watches this and opens the order when it can.
  static final tappedOrder = ValueNotifier<String?>(null);

  /// Starts Messaging and asks for permission.
  ///
  /// It deliberately does **not** register a token. `users.fcm_tokens` is written by the
  /// signed-in account under RLS, and at launch nobody is signed in — a merchant who
  /// installs the app, opens it and then signs in would have had registration run and be
  /// refused, silently. `keepPushTokenRegistered` follows the session instead.
  ///
  /// Returns false when Firebase is not configured in this build, which is a normal
  /// state and not an error — the rest of the app works without it.
  static Future<bool> start() async {
    try {
      await Firebase.initializeApp();
    } catch (error) {
      // No google-services.json, or a build that never registered. Said once, loudly
      // enough to find in a log, and then out of the way.
      debugPrint('Push is off: Firebase is not configured in this build ($error)');
      return false;
    }

    final messaging = FirebaseMessaging.instance;
    // Android 13 and up will not show a notification without this, and the merchant
    // would never know why nothing rang.
    await messaging.requestPermission(alert: true, sound: true, badge: true);

    await _initLocal();

    // A notification tapped while the app was dead is waiting here at launch. Without
    // this the merchant taps the alarm, the app opens on whatever it opened on last, and
    // the order they were told about is not on the screen.
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      tappedOrder.value = launch!.notificationResponse?.payload;
    }

    // The message carries data only, never a `notification` block — with one, Android
    // draws the alert itself and this app never runs, so the looping alarm on the
    // critical channel would never play.
    FirebaseMessaging.onMessage.listen(_show);

    // The one that matters. A data-only message renders nothing by itself, and
    // `onMessage` only fires in the foreground — so without this, an order arriving at a
    // phone in a merchant's pocket, with the app closed, does nothing at all. Which is
    // the entire case this feature exists for.
    FirebaseMessaging.onBackgroundMessage(luqmaBackgroundMessage);

    return true;
  }

  /// This device's token, or null when Firebase is not configured here.
  ///
  /// Asked for on every sign-in rather than cached: Android reissues it after a
  /// reinstall, a restore, or a long silence, and a stale one is a merchant who has gone
  /// quiet with nothing saying so.
  static Future<String?> token() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
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

    await _local.show(
      message.hashCode,
      data['title'] ?? 'لقمة',
      data['body'] ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          'أوردرات',
          importance: Importance.max,
          priority: Priority.high,
          // The channel already carries the sound and the vibration; setting them here
          // as well is how two definitions start disagreeing.
          category: AndroidNotificationCategory.call,
          fullScreenIntent: channel == ordersChannel,
        ),
      ),
      payload: data['orderId'],
    );
  }
}
