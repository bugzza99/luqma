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
abstract final class LuqmaPush {
  const LuqmaPush._();

  /// The channel created natively in MainActivity, at max importance with the alarm
  /// sound. Named here so the payload and the channel cannot drift apart.
  static const ordersChannel = 'orders_critical';

  static final _local = FlutterLocalNotificationsPlugin();

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

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // The message carries data only, never a `notification` block — with one, Android
    // draws the alert itself and this app never runs, so the looping alarm on the
    // critical channel would never play.
    FirebaseMessaging.onMessage.listen(_show);

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
