import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Points the app at the local emulator suite.
///
/// Guarded by an explicit flag rather than by `kDebugMode` alone: a debug build pointed
/// at production is how a developer edits real merchant data thinking it is a sandbox,
/// and a release build pointed at an emulator is an app that cannot reach anything.
/// Neither should ever happen by default.
///
///   flutter run --dart-define=USE_EMULATOR=true
abstract final class Emulators {
  const Emulators._();

  static const enabled = bool.fromEnvironment('USE_EMULATOR');

  /// The host the emulator is reachable at. `localhost` from a desktop or web build;
  /// `10.0.2.2` from the Android emulator, which cannot see the machine's localhost.
  static const host = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

  static Future<void> connect() async {
    if (!enabled) return;
    if (kReleaseMode) {
      // Belt and braces: a release build must never talk to a machine on someone's desk.
      throw StateError('The emulator flag must not be set in a release build.');
    }

    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  }
}
