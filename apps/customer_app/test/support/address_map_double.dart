import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Lets a widget test build a screen that contains a [LuqmaMap].
///
/// There is no native view in a `flutter test`, so `MapLibreMap` has no platform to talk
/// to. This substitutes one that answers every call with an empty future and draws an
/// empty box, which is enough for the widget to be constructed and inspected.
///
/// **It deliberately stops there.** An earlier version also handed the map a fake
/// `MapLibreMapController` and drove `onMapCreated` / `onStyleLoadedCallback` by hand, to
/// assert what got drawn. That is testing MapLibre, not this product: it hung inside the
/// plugin's own `addSymbol`, and a hang there says nothing about whether a customer can
/// read a landmark's name. What the map paints is asserted in `address_map_test.dart`
/// against the pure Dart that paints it.
///
/// Never calling the style callback is also the honest failure case. A phone that cannot
/// reach the tile store never fires `onStyleLoadedCallback`, so the map stays an empty
/// panel for ever — which is exactly the state these tests leave it in, and exactly what
/// the screen around it has to survive.
class AddressMapDouble {
  final _previous = MapLibrePlatform.createInstance;

  void install() => MapLibrePlatform.createInstance = () => _SilentPlatform();

  void restore() => MapLibrePlatform.createInstance = _previous;
}

class _SilentPlatform extends MapLibrePlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #buildView) return const SizedBox.expand();
    return Future<void>.value();
  }
}
