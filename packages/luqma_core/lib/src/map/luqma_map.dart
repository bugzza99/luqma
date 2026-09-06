import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../theme/colors.dart';
import '../theme/dimens.dart';
import 'luqma_map_style.dart';

/// Where the basemap lives.
///
/// One file in this project's own Storage, read by HTTP range requests — the client pulls
/// the slices it needs rather than the whole archive. It is here rather than in
/// `LuqmaConfig` on purpose: a remote value somebody can change is right for a number
/// like a delivery fee and wrong for the address of the file the map cannot render
/// without. A bad value there would be a blank map on every phone until someone noticed.
const luqmaBasemapUrl =
    'https://vqcivwdoekyfqhfmnuos.supabase.co/storage/v1/object/public/map/edku.pmtiles';

/// Edku, and the box the basemap actually covers.
///
/// `final` rather than `const`: MapLibre's `LatLngBounds` has no const constructor.
///
/// The archive holds this rectangle and nothing else, so the camera target is fenced to
/// it. That fences the *centre*, not the viewport — at a low enough zoom a wide screen
/// still sees past a corner, which is why the minimum zoom is 11 rather than 10.
final luqmaCityBounds = LatLngBounds(
  southwest: const LatLng(31.15, 30.10),
  northeast: const LatLng(31.40, 30.48),
);

const luqmaCityCentre = LatLng(31.3057, 30.2986);

/// A place on the map that belongs to Luqma rather than to OpenStreetMap.
@immutable
class LuqmaMapMarker {
  const LuqmaMapMarker({
    required this.id,
    required this.lat,
    required this.lng,
    required this.label,
    this.emphasised = false,
  });

  final String id;
  final double lat;
  final double lng;

  /// What this place is called, in Arabic.
  ///
  /// **Not drawn on the map.** A native symbol carrying `textField` makes MapLibre build
  /// a symbol layer, and a symbol layer needs glyphs fetched over HTTP — which would put
  /// a font server back in the path of a map hosted precisely so no third party can
  /// switch it off. The first version of this widget set `textField` on every marker
  /// while its own documentation claimed nothing reached for a glyph server. The two
  /// contradicted each other, and the documentation was the one telling the truth about
  /// the intent.
  ///
  /// So the map draws pins, [LuqmaMap.onMarkerTap] says which one was pressed, and the
  /// screen renders the name in its own Arabic text. The label has a reader; it is simply
  /// not the map renderer.
  final String label;

  /// The one this screen is about: the address being confirmed, the delivery being made.
  final bool emphasised;
}

/// The branded map, with Luqma's own places on top of it.
///
/// The basemap is geometry only — see [luqmaMapStyle] — so every word anybody reads here
/// comes from this product. That is the arrangement `docs/09` asked for: the map gives a
/// courier the shape of the city, and the landmarks give them the sentence they actually
/// navigate by.
class LuqmaMap extends StatefulWidget {
  const LuqmaMap({
    super.key,
    this.markers = const [],
    this.initialCentre,
    this.initialZoom = 13,
    this.onTap,
    this.onMarkerTap,
    this.height,
  });

  final List<LuqmaMapMarker> markers;
  final LatLng? initialCentre;
  final double initialZoom;

  /// Called with where somebody pressed. Null makes the map a picture rather than a
  /// control — right for a courier reading a destination, wrong for a customer dropping
  /// a pin.
  final void Function(double lat, double lng)? onTap;

  /// Called with the marker somebody pressed. How a name reaches the screen, since the
  /// map deliberately draws no text of its own.
  final void Function(LuqmaMapMarker marker)? onMarkerTap;

  final double? height;

  @override
  State<LuqmaMap> createState() => _LuqmaMapState();
}

class _LuqmaMapState extends State<LuqmaMap> {
  MapLibreMapController? _controller;

  /// A controller existing is not the same as its style being ready.
  ///
  /// `onMapCreated` fires first, and the plugin throws if a symbol is added before its
  /// annotation manager exists. A widget update landing between those two moments used to
  /// start drawing anyway, which is an unhandled async error rather than a missing pin.
  bool _styleReady = false;

  /// Serialises redraws.
  ///
  /// Two callbacks can begin the clear-and-add sequence at once — a style load and a
  /// parent rebuild — and each awaits several platform calls. Interleaved, an older draw
  /// resumes after a newer one has cleared and its markers come back from the dead. This
  /// counter lets a draw notice it has been superseded and stop.
  int _drawGeneration = 0;

  final Map<String, LuqmaMapMarker> _bySymbolId = {};

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: Radii.cardAll,
        child: Stack(
          children: [
            MapLibreMap(
              styleString: luqmaMapStyle(
                colors: colors,
                pmtilesUrl: luqmaBasemapUrl,
                dark: dark,
              ),
              initialCameraPosition: CameraPosition(
                target: widget.initialCentre ?? luqmaCityCentre,
                zoom: widget.initialZoom,
              ),
              cameraTargetBounds: CameraTargetBounds(luqmaCityBounds),
              minMaxZoomPreference: const MinMaxZoomPreference(11, 18),
              // Nothing here needs a compass, a scale bar or the platform's own
              // attribution chrome: the map is a panel inside a screen, and every control
              // it draws is one more thing between somebody and the address they came for.
              compassEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              onMapCreated: (c) {
                _controller = c;
                c.onSymbolTapped.add(_symbolTapped);
              },
              onStyleLoadedCallback: () {
                _styleReady = true;
                _redraw();
              },
              onMapClick: (_, latLng) =>
                  widget.onTap?.call(latLng.latitude, latLng.longitude),
            ),
            // ODbL asks for visible attribution on a produced work, and that is the whole
            // price of a map needing no key, no account and no card. Drawn rather than
            // left to the platform button so it is legible against the brand ground.
            Positioned(
              bottom: 0,
              left: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.card.withValues(alpha: .82),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.xs,
                    vertical: 2,
                  ),
                  child: Text(
                    '© OpenStreetMap',
                    style: TextStyle(fontSize: 10, color: colors.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(LuqmaMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.markers, widget.markers)) _redraw();
  }

  @override
  void dispose() {
    _controller?.onSymbolTapped.remove(_symbolTapped);
    super.dispose();
  }

  void _symbolTapped(Symbol symbol) {
    final marker = _bySymbolId[symbol.id];
    if (marker != null) widget.onMarkerTap?.call(marker);
  }

  /// Draws the current markers, abandoning the attempt the moment a newer one starts.
  ///
  /// Symbols rather than Flutter widgets pinned to coordinates: a widget layer has to be
  /// repositioned on every frame of a pan, which on a mid-range Android phone is where a
  /// map starts dropping frames. These are drawn by the native renderer with the roads.
  Future<void> _redraw() async {
    final controller = _controller;
    if (controller == null || !_styleReady || !mounted) return;

    final generation = ++_drawGeneration;
    // Read before the first await, while this context is certainly still mounted.
    final colors = Theme.of(context).luqma;

    // `marker-15` used to be named here — an identifier from a sprite sheet this style
    // does not declare and nothing ever registered, so no pin could render at all. The
    // image is drawn in Dart and handed to the renderer instead, which also means it
    // carries the brand's colour rather than whatever a sprite happened to contain.
    final pin = await _pinImage(colors.brand);
    final emphasised = await _pinImage(colors.accent, scale: 1.35);
    if (generation != _drawGeneration || !mounted) return;

    await controller.addImage('luqma-pin', pin);
    await controller.addImage('luqma-pin-emphasised', emphasised);
    if (generation != _drawGeneration) return;

    await controller.clearSymbols();
    _bySymbolId.clear();
    if (generation != _drawGeneration) return;

    for (final marker in widget.markers) {
      if (generation != _drawGeneration) return;
      final symbol = await controller.addSymbol(
        SymbolOptions(
          geometry: LatLng(marker.lat, marker.lng),
          iconImage: marker.emphasised ? 'luqma-pin-emphasised' : 'luqma-pin',
          iconSize: 1,
          // Anchored at its point rather than centred on it: a pin whose middle sits on
          // the destination is a pin aiming half a street away.
          iconAnchor: 'bottom',
        ),
      );
      // Checked *after* the await as well as before it. The native map is safe either
      // way — a newer draw's `clearSymbols` wipes whatever an abandoned one added — but
      // this registry is not: an add that lands after a newer draw has cleared it would
      // leave a dead entry behind, and `_symbolTapped` would answer a press with the
      // wrong marker's name.
      if (generation != _drawGeneration) return;
      _bySymbolId[symbol.id] = marker;
    }
  }

  /// A teardrop pin, as PNG bytes.
  ///
  /// Drawn here so the map needs no sprite sheet and no bundled asset: one less file to
  /// host, and the colour comes from the theme like everything else in the product.
  static Future<Uint8List> _pinImage(Color colour, {double scale = 1}) async {
    final size = 48.0 * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final radius = size / 3;
    final centre = Offset(size / 2, radius + size * .06);

    canvas.drawPath(
      Path()
        ..addOval(Rect.fromCircle(center: centre, radius: radius))
        ..moveTo(size / 2 - radius * .55, centre.dy + radius * .78)
        ..lineTo(size / 2, size)
        ..lineTo(size / 2 + radius * .55, centre.dy + radius * .78)
        ..close(),
      Paint()..color = colour,
    );
    // A hole rather than a dot, so the ground shows through and the pin reads on both the
    // cream and the dark grounds without a second colour to keep in step with the theme.
    canvas.drawCircle(
      centre,
      radius * .36,
      Paint()..blendMode = BlendMode.clear,
    );

    final image =
        await recorder.endRecording().toImage(size.ceil(), size.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }
}
