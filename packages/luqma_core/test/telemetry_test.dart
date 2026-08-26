import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The telemetry door is a no-op without its dart-define.
///
/// A test run has no `LUQMA_SENTRY_DSN`, which is exactly the condition a dev build
/// runs under — so proving init does not throw and events do nothing proves what
/// actually happens on every developer machine.
void main() {
  test('without a DSN the SDK stays off', () async {
    expect(LuqmaTelemetry.enabled, isFalse);
    await expectLater(LuqmaTelemetry.init(), completes);
    // And an event with the door shut is simply dropped, never thrown.
    LuqmaTelemetry.event('test.event');
  });
}
