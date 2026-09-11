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
/// Which maps application handles the hand-off.
enum MapApp {
  googleMaps,
  waze,
}

/// Hands an address to whatever maps app is on the phone.
///
/// A hand-off rather than a map in the app, and that is the whole decision. Google Maps
/// and Waze are already installed, already know the roads, are free, and talk — none of
/// which a map inside this app would be. What this app is for is the order, not the driving.
///
/// An interface only so the screens above can be tested; there is nothing else to swap.
abstract interface class MapNavigator {
  /// [query] is the address in words. [lat]/[lng] are the pin, when the order carries
  /// one — both halves or neither, which is how they are stored and frozen.
  Future<void> navigateTo(
    String query, {
    double? lat,
    double? lng,
    MapApp app = MapApp.googleMaps,
  });
}

class ExternalMapNavigator implements MapNavigator {
  const ExternalMapNavigator({this.links = const PhoneExternalLinks()});

  final ExternalLinks links;

  /// Google Maps URL with pin if available, falling back to query.
  @visibleForTesting
  static Uri googleMapsUriFor(String query, {double? lat, double? lng}) {
    final pin = lat != null && lng != null ? '$lat,$lng' : null;
    return Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${Uri.encodeComponent(pin ?? query)}',
    );
  }

  /// Waze universal deep link with pin (ll) if available, falling back to search query (q).
  @visibleForTesting
  static Uri wazeUriFor(String query, {double? lat, double? lng}) {
    final pin = lat != null && lng != null ? '$lat,$lng' : null;
    return Uri.parse(
      pin != null
          ? 'https://waze.com/ul?ll=$pin&navigate=yes'
          : 'https://waze.com/ul?q=${Uri.encodeComponent(query)}&navigate=yes',
    );
  }

  @override
  Future<void> navigateTo(
    String query, {
    double? lat,
    double? lng,
    MapApp app = MapApp.googleMaps,
  }) async {
    final uri = switch (app) {
      MapApp.googleMaps => googleMapsUriFor(query, lat: lat, lng: lng),
      MapApp.waze => wazeUriFor(query, lat: lat, lng: lng),
    };
    // No maps app and no browser is possible on a cheap handset, and the courier is
    // in the street. `ExternalLinks` swallows the PlatformException so the tap does not
    // crash the delivery screen; the address is already written above the button, which
    // is what a person falls back to.
    await links.open(uri);
  }
}

/// Records what it was asked to open.
@visibleForTesting
class FakeNavigator implements MapNavigator {
  String? lastQuery;
  double? lastLat;
  double? lastLng;
  MapApp? lastApp;

  @override
  Future<void> navigateTo(
    String query, {
    double? lat,
    double? lng,
    MapApp app = MapApp.googleMaps,
  }) async {
    lastQuery = query;
    lastLat = lat;
    lastLng = lng;
    lastApp = app;
  }
}

@Riverpod(keepAlive: true)
MapNavigator mapNavigator(Ref ref) =>
    ExternalMapNavigator(links: ref.watch(externalLinksProvider));
