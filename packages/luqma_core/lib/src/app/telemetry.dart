import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Crash reporting and analytics, in one small door.
///
/// Sentry was chosen over re-adding Firebase precisely because the cutover removed
/// Firebase; the DSN arrives as a dart-define, so the same binary is instrumented in
/// release and silent in development — an empty `LUQMA_SENTRY_DSN` turns the whole
/// thing off, and a developer running on a simulator sends nothing anywhere.
///
/// Events beyond crashes: call [event] at the moments worth counting (an order placed,
/// a coupon refused). Deliberately few — analytics that count everything are read by
/// nobody, and Edku's numbers are small enough to know by heart.
abstract final class LuqmaTelemetry {
  static const _dsn = String.fromEnvironment('LUQMA_SENTRY_DSN');

  static bool get enabled => _dsn.isNotEmpty;

  /// Configures the SDK. Safe to call unconditionally: without a DSN it does nothing,
  /// which is exactly what a dev build wants.
  static Future<void> init() async {
    if (_dsn.isEmpty) return;

    await SentryFlutter.init(
      (options) {
        options.dsn = _dsn;
        options.environment = kReleaseMode ? 'production' : 'development';
        options.tracesSampleRate = 0.1;
      },
    );
  }

  /// One named moment worth counting. A no-op when telemetry is off.
  static void event(String name, {Map<String, Object>? data}) {
    if (!enabled) return;
    Sentry.captureMessage(name, withScope: (scope) {
      if (data != null) scope.setContexts('details', data);
    });
  }
}
