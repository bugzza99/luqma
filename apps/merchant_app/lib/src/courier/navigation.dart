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
  /// [query] is the address in words. [lat]/[lng] are the pin, when the order carries
  /// one — both halves or neither, which is how they are stored and frozen.
  Future<void> navigateTo(String query, {double? lat, double? lng});
}

class GoogleMapsNavigator implements MapNavigator {
  const GoogleMapsNavigator();

  /// What gets opened.
  ///
  /// A coordinate when the order has one, and the words when it does not. For phases
  /// this was words only, with a comment saying a pin dropped on a guess is worse than a
  /// name a person can read — true, and not the situation any more: the pins are the
  /// admin's own landmarks, placed deliberately, and they arrive on the order frozen.
  ///
  /// The words are the weaker half here and always were. **Google does not know
  /// «صيدلية النور»** — these names are local knowledge, not map data — so searching one
  /// lands the courier somewhere in the governorate or nowhere at all. A real coordinate
  /// is the first thing this hand-off has ever had that the maps app can actually use.
  @visibleForTesting
  static Uri uriFor(String query, {double? lat, double? lng}) {
    final pin = lat != null && lng != null ? '$lat,$lng' : null;
    return Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent(pin ?? query)}',
    );
  }

  @override
  Future<void> navigateTo(String query, {double? lat, double? lng}) async {
    final uri = uriFor(query, lat: lat, lng: lng);
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
  double? lastLat;
  double? lastLng;

  @override
  Future<void> navigateTo(String query, {double? lat, double? lng}) async {
    lastQuery = query;
    lastLat = lat;
    lastLng = lng;
  }
}

@Riverpod(keepAlive: true)
MapNavigator mapNavigator(Ref ref) => const GoogleMapsNavigator();
