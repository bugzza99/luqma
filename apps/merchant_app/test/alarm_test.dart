import 'package:flutter_test/flutter_test.dart';
import 'package:merchant_app/src/alarm/alarm.dart';

/// What happens to the alarm when the device refuses to play it.
///
/// The rules about *when* the sound plays are in `order_alarm_test.dart`, argued with
/// against `FakeAlarm`, which cannot fail. This file is the other half: the real state
/// machine on a phone where playback throws — the audio session held by a call, a
/// missing asset in a bad build, an OEM that will not give out the alarm stream.
///
/// It matters more than its size suggests. `_playing` is the guard that keeps a second
/// order from clipping the loop back to its start during a rush. If a failed start
/// leaves that guard set it latches: every later start returns at it, and the merchant
/// hears nothing for the rest of the session while the screen goes on showing orders.
/// The one thing this app exists to do stops, silently.
class _FakeDevice implements AlarmDevice {
  int plays = 0;
  int stops = 0;
  bool failOnPlay = false;
  bool failOnStop = false;

  @override
  Future<void> play() async {
    plays++;
    if (failOnPlay) throw Exception('no audio device');
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failOnStop) throw Exception('device went away');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('a start that fails does not latch the alarm off for the session', () async {
    final device = _FakeDevice()..failOnPlay = true;
    final alarm = LoopingAlarm(device);

    await expectLater(alarm.start(), throwsA(isA<Exception>()));
    expect(alarm.isPlaying, isFalse,
        reason: 'it never started, so it must not claim to be playing');

    // The next order is the whole point. Before the fix this returned at the guard and
    // the device was never asked a second time.
    await expectLater(alarm.start(), throwsA(isA<Exception>()));
    expect(device.plays, 2, reason: 'the next order asked the device again');
  });

  test('and the order after a failure rings once the device comes back', () async {
    final device = _FakeDevice()..failOnPlay = true;
    final alarm = LoopingAlarm(device);

    await expectLater(alarm.start(), throwsA(isA<Exception>()));

    device.failOnPlay = false;
    await alarm.start();

    expect(alarm.isPlaying, isTrue,
        reason: 'a call ends, focus comes back, and the next order must be heard');
  });

  test('a start that succeeds still guards against restarting mid-rush', () async {
    final device = _FakeDevice();
    final alarm = LoopingAlarm(device);

    await alarm.start();
    await alarm.start();

    expect(device.plays, 1,
        reason: 'restarting would clip the loop back to its beginning every time '
            'another order landed during a rush');
    expect(alarm.isPlaying, isTrue);
  });

  test('stopping clears the flag even when the device throws on the way down', () async {
    final device = _FakeDevice()..failOnStop = true;
    final alarm = LoopingAlarm(device);

    await alarm.start();
    await expectLater(alarm.stop(), throwsA(isA<Exception>()));

    expect(alarm.isPlaying, isFalse,
        reason: 'a stop that threw must not leave the alarm believing it is still '
            'playing — the next order would find the guard set');
  });

  test('stopping something that was never started asks the device nothing', () async {
    final device = _FakeDevice();
    await LoopingAlarm(device).stop();
    expect(device.stops, 0);
  });
}
