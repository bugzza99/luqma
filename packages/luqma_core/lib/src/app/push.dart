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
  await Firebase.initializeApp();
  await LuqmaPush.render(message);
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
  /// signed-in account under RLS, and at launch nobody is signed in — somebody who
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
      // enough to find in a log, and then out of the way. This is a normal state for a
      // developer's machine and for any app whose config has not been added yet — the
      // rest of the app works without it.
      debugPrint('Push is off: Firebase is not configured in this build ($error)');
      return false;
    }

    final messaging = FirebaseMessaging.instance;
    // Android 13 and up will not show a notification without this, and nobody would ever
    // learn why nothing rang.
    await messaging.requestPermission(alert: true, sound: true, badge: true);

    await _initLocal();

    // A notification tapped while the app was dead is waiting here at launch. Without
    // this somebody taps the alert, the app opens on whatever it opened on last, and the
    // order they were told about is not on the screen.
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      tappedOrder.value = launch!.notificationResponse?.payload;
    }

    // The message carries data only, never a `notification` block — with one, Android
    // draws the alert itself and this app never runs, so the looping alarm on the
    // critical channel would never play.
    FirebaseMessaging.onMessage.listen(_show);

    // The one that matters. A data-only message renders nothing by itself, and
    // `onMessage` only fires in the foreground — so without this, a message arriving at a
    // phone in a pocket with the app closed does nothing at all, which is the entire case
    // this feature exists for.
    FirebaseMessaging.onBackgroundMessage(luqmaBackgroundMessage);

    return true;
  }

  /// This device's token, or null when Firebase is not configured here.
  ///
  /// Asked for on every sign-in rather than cached: Android reissues it after a
  /// reinstall, a restore, or a long silence, and a stale one is a phone that has gone
  /// quiet with nothing anywhere saying so.
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
          channel == ordersChannel ? 'أوردرات' : 'تنبيهات',
          importance: Importance.max,
          priority: Priority.high,
          // The channel already carries the sound and the vibration; setting them here
          // as well is how two definitions start disagreeing.
          //
          // The full-screen intent and the call category are the alarm's, and only the
          // alarm's: they take over the lock screen, which is right for a kitchen that
          // has to answer in ninety seconds and wrong for telling a customer their food
          // has left the shop.
          category: channel == ordersChannel
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.status,
          fullScreenIntent: channel == ordersChannel,
        ),
      ),
      payload: data['orderId'],
    );
  }
}
