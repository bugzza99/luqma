import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every channel the server can name has to exist on the phone that receives it.
///
/// A notification carries `android.notification.channel_id`, and when the app has never
/// created that channel FCM does not fail — it falls back to the id named in the
/// manifest as the default. So a message asking for a quiet channel that the app lacks
/// arrives on whatever the default happens to be, which in MerchantApp and AdminApp is
/// the alarm.
///
/// That is not hypothetical. The commission reminder and the advert request are written
/// into `push_outbox` on `orders` deliberately — the trigger's own comment says an advert
/// can wait and that sharing the alarm teaches somebody to ignore it — and for weeks
/// neither app created an `orders` channel, so both arrived on `orders_critical`:
/// bypassing Do Not Disturb, on the alarm stream, at the volume set for being woken up.
/// The intent was right and the effect was the exact thing it warned against.
///
/// Written as a scan over the Kotlin and the manifests rather than as a widget test,
/// because nothing in Dart can observe this. The channel is created natively before
/// Flutter starts, and the failure only appears on a real handset, weeks later, as "the
/// alarm goes off for things that are not orders".
void main() {
  // The suite runs from `packages/luqma_core`.
  final apps = Directory('../../apps');

  String kotlin(String app, String package) => File(
        '${apps.path}/$app/android/app/src/main/kotlin/com/luqma/$package/MainActivity.kt',
      ).readAsStringSync();

  String manifest(String app) =>
      File('${apps.path}/$app/android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

  /// The ids the Kotlin actually creates a `NotificationChannel` for.
  ///
  /// Read from the `CHANNEL_ID` constants, which is where the strings live, and then
  /// checked against `createNotificationChannel` so a constant nobody uses cannot
  /// satisfy this test.
  Set<String> declared(String source) => RegExp(r'CHANNEL_ID = "([a-z_]+)"')
      .allMatches(source)
      .map((m) => m.group(1)!)
      .toSet();

  /// The id FCM falls back to when the message names a channel that does not exist.
  String fallback(String source) => RegExp(
        r'default_notification_channel_id"\s*\n?\s*android:value="([a-z_]+)"',
      ).firstMatch(source)!.group(1)!;

  const targets = [
    (app: 'customer_app', package: 'customer', needs: {'orders', 'marketing'}),
    (app: 'merchant_app', package: 'merchant', needs: {'orders', 'orders_critical'}),
    (app: 'admin_app', package: 'admin', needs: {'orders', 'orders_critical'}),
  ];

  for (final target in targets) {
    group(target.app, () {
      test('creates every channel the server sends it', () {
        final source = kotlin(target.app, target.package);
        final ids = declared(source);

        for (final id in target.needs) {
          expect(
            ids,
            contains(id),
            reason: '${target.app} receives messages on "$id". Without the channel, FCM '
                'falls back to ${fallback(manifest(target.app))} and the notification '
                'arrives with the wrong sound and the wrong urgency.',
          );
          expect(
            source,
            contains('createNotificationChannel'),
            reason: 'a constant is not a channel',
          );
        }
      });

      test('its manifest fallback is a channel it really creates', () {
        // The last line of defence: whatever FCM falls back to must at least be
        // configured. An id in the manifest that nothing creates puts every unmatched
        // message on a channel Android invents, with default importance and no sound.
        expect(declared(kotlin(target.app, target.package)),
            contains(fallback(manifest(target.app))));
      });
    });
  }

  test('the quiet channel is never the alarm', () {
    // The whole point of `orders` on a staff app is that it is *not* the alarm. If
    // somebody ever points both ids at one channel, the split stops meaning anything and
    // muting the billing reminder mutes the kitchen.
    for (final target in targets.where((t) => t.app != 'customer_app')) {
      final ids = declared(kotlin(target.app, target.package));
      expect(ids.contains('orders') && ids.contains('orders_critical'), isTrue,
          reason: '${target.app} must keep the two apart');
    }
  });

  test('only the merchant claims the alarm stream', () {
    // `USAGE_ALARM` stays audible on vibrate and at the volume somebody set for being
    // woken up. It belongs to the one notification a shop's evening depends on, and
    // nowhere else — an admin alert or a billing notice on that stream is how a person
    // learns to turn the whole app off.
    expect(kotlin('merchant_app', 'merchant'), contains('USAGE_ALARM'));
    expect(kotlin('admin_app', 'admin'), isNot(contains('USAGE_ALARM')));
    expect(kotlin('customer_app', 'customer'), isNot(contains('USAGE_ALARM')));
  });
}
