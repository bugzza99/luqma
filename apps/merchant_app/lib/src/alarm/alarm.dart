import 'package:audioplayers/audioplayers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'alarm.g.dart';

/// The sound a new order makes.
///
/// An interface because the thing underneath needs an audio device, and because the
/// rules about *when* it plays are the part that actually matters — those get tested
/// without one.
abstract interface class Alarm {
  bool get isPlaying;

  /// Starts, and keeps going until [stop]. Starting one that is already playing does
  /// nothing: restarting would clip the loop back to its beginning every time another
  /// order landed during a rush.
  Future<void> start();

  Future<void> stop();
}

/// The device underneath, as the two calls this class actually makes.
///
/// A seam rather than an `AudioPlayer` parameter, because `AudioPlayer()`'s constructor
/// reaches the platform channel the moment it is built — so a test cannot even
/// *construct* a stand-in for it, let alone make one fail. Everything worth arguing with
/// here is the state machine above it, and this is what lets that be argued with.
abstract interface class AlarmDevice {
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

/// `assets/audio/new_order.wav`, on a loop, through the alarm channel.
class AudioPlayerDevice implements AlarmDevice {
  AudioPlayerDevice([AudioPlayer? player]) : _player = player ?? AudioPlayer() {
    // The alarm stream, not media: it stays audible when the phone is on vibrate and it
    // does not duck for whatever else is playing. This sound exists to interrupt.
    _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.duckOthers},
        ),
      ),
    );
    _player.setReleaseMode(ReleaseMode.loop);
  }

  final AudioPlayer _player;

  @override
  Future<void> play() =>
      _player.play(AssetSource('audio/new_order.wav'), volume: 1);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Keeps the sound going until it is told to stop.
class LoopingAlarm implements Alarm {
  LoopingAlarm([AlarmDevice? device]) : _device = device ?? AudioPlayerDevice();

  final AlarmDevice _device;

  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    try {
      await _device.play();
    } catch (_) {
      // The flag is the guard that stops a second order clipping the loop back to its
      // beginning during a rush. Left set after a failure it latches: every later
      // `start()` returns here, and the merchant hears nothing for the rest of the
      // session while the screen goes on showing orders. A device that refused once may
      // well take the next one — a call has ended, focus has come back — so the honest
      // state after a failed start is "not playing".
      _playing = false;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_playing) return;
    // Cleared before the call and not after it, for the same reason: a stop that throws
    // must not leave this believing the sound is still going.
    _playing = false;
    await _device.stop();
  }

  Future<void> dispose() => _device.dispose();
}

/// Counts what it was asked to do, so the rules above it can be tested without a device.
class FakeAlarm implements Alarm {
  bool _playing = false;

  int starts = 0;
  int stops = 0;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    starts++;
  }

  @override
  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    stops++;
  }
}

@Riverpod(keepAlive: true)
Alarm alarm(Ref ref) {
  final alarm = LoopingAlarm();
  ref.onDispose(alarm.dispose);
  return alarm;
}
