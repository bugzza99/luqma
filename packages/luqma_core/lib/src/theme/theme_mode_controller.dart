import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_mode_store.dart';

/// The store the controller writes through. Overridden at start-up, and in tests.
final themeModeStoreProvider = Provider<ThemeModeStore>(
  (ref) => throw StateError(
    'themeModeStoreProvider was read before it was overridden. '
    '`luqmaBootstrap` supplies it; a widget test supplies a FakeThemeModeStore.',
  ),
);

/// Light, dark, or the phone's own setting.
///
/// Starts at [ThemeMode.system] and settles to the stored value once the platform store
/// answers, rather than blocking the first frame on a disk read. The app looks the same
/// either way for anyone who never chose — which is nearly everyone — and somebody who
/// did chose light on a dark phone sees at most one frame of the other before it lands.
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Not awaited: `build` is synchronous, and a theme that arrives a frame late is a
    // better trade than a splash that waits on local storage.
    unawaited(_restore());
    return ThemeMode.system;
  }

  /// Guarded whole, because it is fired and forgotten.
  ///
  /// `CLAUDE.md` records what an unawaited future that throws costs in these builds:
  /// Sentry reports an unhandled async error through `PlatformDispatcher.onError` as
  /// **fatal**, which is how three release APKs died on launch. Nothing about a colour
  /// scheme is worth that, so every path out of here is a theme rather than an error.
  Future<void> _restore() async {
    try {
      final stored = await ref.read(themeModeStoreProvider).load();
      // Only if nobody has chosen in the meantime. Somebody fast enough to open حسابي
      // and press a mode before the disk answers must not have their choice overwritten
      // by the value that was there before it.
      if (state == ThemeMode.system && stored != ThemeMode.system) state = stored;
    } catch (_) {
      // The system theme is already what `build` returned.
    }
  }

  /// Sets the mode and remembers it. The screen changes immediately; the write is what
  /// makes it survive the next launch.
  ///
  /// Guarded for the same reason [_restore] is, and more sharply: this one hangs off a
  /// tap. A chip handler that returns a future nobody awaits is an unhandled async error
  /// if it throws, which these builds report as fatal — so a phone whose platform store
  /// refuses a write would crash on a press that changed a colour. The screen keeps the
  /// choice either way; what is lost is the next launch remembering it.
  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await ref.read(themeModeStoreProvider).save(mode);
    } catch (_) {
      // Nothing to say: the app is already in the mode that was asked for.
    }
  }
}
