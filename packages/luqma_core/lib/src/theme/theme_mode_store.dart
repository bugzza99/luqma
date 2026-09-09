import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the customer's choice of light, dark or "whatever the phone says" is kept.
///
/// Deliberately a *third* state rather than a switch between two. A phone that turns
/// dark at sunset is a setting somebody already made once, for every app they own, and an
/// app that ignores it is an app they have to correct twice a day. So the default follows
/// the phone, and choosing explicitly is what stops it following — which is also the only
/// way to answer "I want this one app light while everything else is dark".
///
/// `SharedPreferencesAsync`, matching the courier's queue: the legacy API caches in memory
/// and writes through afterwards, and a preference that loses the last change on a kill is
/// a setting that appears not to have worked.
abstract interface class ThemeModeStore {
  Future<ThemeMode> load();
  Future<void> save(ThemeMode mode);
}

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  SharedPreferencesThemeModeStore({SharedPreferencesAsync? prefs})
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const _key = 'luqma.themeMode';

  @override
  Future<ThemeMode> load() async {
    // Never allowed to throw. A phone that cannot read this preference is a phone that
    // opens the app on the system theme, which is exactly where it starts anyway — and
    // the alternative is `luqmaBootstrap` drawing its failure screen because a colour
    // scheme could not be read.
    try {
      return switch (await _prefs.getString(_key)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      return ThemeMode.system;
    }
  }

  @override
  Future<void> save(ThemeMode mode) async {
    try {
      await _prefs.setString(_key, mode.name);
    } catch (_) {
      // The screen has already changed; losing the preference costs the next launch,
      // not this one, and there is nothing useful to say about it here.
    }
  }
}

/// Remembers nothing, for tests and for a build with no platform store.
class FakeThemeModeStore implements ThemeModeStore {
  FakeThemeModeStore([this.mode = ThemeMode.system]);

  ThemeMode mode;

  @override
  Future<ThemeMode> load() async => mode;

  @override
  Future<void> save(ThemeMode next) async => mode = next;
}
