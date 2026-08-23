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

/// Plays `assets/audio/new_order.wav` on a loop, through the alarm channel.
class LoopingAlarm implements Alarm {
  LoopingAlarm([AudioPlayer? player]) : _player = player ?? AudioPlayer() {
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

  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    await _player.play(AssetSource('audio/new_order.wav'), volume: 1);
  }

  @override
  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    await _player.stop();
  }

  Future<void> dispose() => _player.dispose();
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
