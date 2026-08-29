import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:luqma_core/luqma_core.dart';

part 'navigation.g.dart';

/// Hands an address to whatever maps app is on the phone.
///
/// A hand-off rather than a map in the app, and that is the whole decision. Google Maps
/// is already installed, already knows the roads, is free, and talks — none of which a
/// map inside this app would be. What this app is for is the order, not the driving.
///
/// An interface only so the screens above can be tested; there is nothing else to swap.
abstract interface class MapNavigator {
  Future<void> navigateTo(String query);
}

class GoogleMapsNavigator implements MapNavigator {
  const GoogleMapsNavigator();

  @override
  Future<void> navigateTo(String query) async {
    // A search query, not coordinates. The addresses here are a zone and a landmark —
    // "next to Al-Nour pharmacy" — because Edku's streets are not systematically
    // numbered, and a pin dropped on a guess is worse than a name a person can read.
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    // No maps app and no browser is possible on a cheap handset, and the courier is
    // in the street. `ExternalLinks` swallows the PlatformException so the tap does not
    // crash the delivery screen; the address is already written above the button, which
    // is what a person falls back to.
    await const PhoneExternalLinks().open(uri);
  }
}

/// Records what it was asked to open.
@visibleForTesting
class FakeNavigator implements MapNavigator {
  String? lastQuery;

  @override
  Future<void> navigateTo(String query) async => lastQuery = query;
}

@Riverpod(keepAlive: true)
MapNavigator mapNavigator(Ref ref) => const GoogleMapsNavigator();
