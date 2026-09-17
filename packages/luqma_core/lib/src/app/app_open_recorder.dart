import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../util/cairo_day.dart';

typedef RecordAppOpenRpc = Future<void> Function(String app, String deviceId);

/// Records that the app was opened on a handset.
///
/// Records at most once per Cairo day per app per process — and once more that day when
/// somebody signs in, because the server only learns whose device it is from a call made
/// with a session. Stores a persistent UUID v4 under `luqma.device_id`. Never throws:
/// `main` fires this and forgets it, and an unhandled async error there is a fatal crash
/// in these builds (CLAUDE.md).
class AppOpenRecorder {
  AppOpenRecorder({
    required this.prefs,
    SupabaseClient? client,
    RecordAppOpenRpc? rpc,
    DateTime Function()? clock,
    bool Function()? hasUser,
  })  : _hasUser = hasUser ?? (() => client?.auth.currentUser != null),
        _rpc = rpc ??
            ((app, deviceId) => client!.rpc('record_app_open', params: {
                  'p_app': app,
                  'p_device_id': deviceId,
                })),
        _clock = clock ?? DateTime.now;

  static const prefDeviceId = 'luqma.device_id';

  final SharedPreferences prefs;
  final RecordAppOpenRpc _rpc;
  final DateTime Function() _clock;

  final bool Function() _hasUser;

  /// (app, Cairo day, signed in) combinations already sent, or being sent now.
  final Set<String> _done = {};
  final Set<String> _inFlight = {};

  /// Retrieves or generates a persistent device UUID v4.
  ///
  /// The write is awaited: a discarded `setString` future that fails escapes every
  /// surrounding `catch` into the zone.
  Future<String> deviceId() async {
    var id = prefs.getString(prefDeviceId);
    if (id == null || id.isEmpty) {
      id = generateUuidV4();
      await prefs.setString(prefDeviceId, id);
    }
    return id;
  }

  /// Generates a RFC 4122 version 4 UUID using [Random.secure()].
  static String generateUuidV4([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xxxxxx
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Records an open of [app] ('customer' or 'merchant') for the current Cairo day.
  ///
  /// Never throws — failures are caught and swallowed so launch or resume paths
  /// never crash.
  Future<void> record(String app) async {
    String? key;
    try {
      key = '$app|${cairoDay(_clock())}|${_hasUser()}';
      if (_done.contains(key) || _inFlight.contains(key)) return;
      _inFlight.add(key);
      await _rpc(app, await deviceId());
      _done.add(key);
    } catch (_) {
      // Swallowed by design: unawaited ping must never throw. Not marked done, so the next
      // open tries again.
    } finally {
      if (key != null) _inFlight.remove(key);
    }
  }

  /// Attaches a [WidgetsBindingObserver] helper to record on app resume.
  WidgetsBindingObserver attachLifecycleObserver(String app, [WidgetsBinding? binding]) {
    final observer = AppOpenLifecycleObserver(recorder: this, app: app);
    (binding ?? WidgetsBinding.instance).addObserver(observer);
    return observer;
  }

  /// Convenience start method for app entry points.
  static Future<AppOpenRecorder?> start(
    SupabaseClient client,
    String app, {
    SharedPreferences? prefs,
    WidgetsBinding? binding,
  }) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final recorder = AppOpenRecorder(client: client, prefs: p);
      recorder.attachLifecycleObserver(app, binding);
      // A sign-in later in the day is what tells the server whose device this is.
      client.auth.onAuthStateChange.listen(
        (state) {
          if (state.event == AuthChangeEvent.signedIn) unawaited(recorder.record(app));
        },
        onError: (Object _) {},
      );
      unawaited(recorder.record(app));
      return recorder;
    } catch (_) {
      // never throws
      return null;
    }
  }
}

/// Helper observing lifecycle transitions and recording app open on resume.
class AppOpenLifecycleObserver with WidgetsBindingObserver {
  AppOpenLifecycleObserver({
    required this.recorder,
    required this.app,
  });

  final AppOpenRecorder recorder;
  final String app;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(recorder.record(app));
    }
  }
}
