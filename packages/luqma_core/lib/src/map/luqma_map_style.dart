import 'dart:convert';

import '../theme/colors.dart';

/// The basemap, in Luqma's colours.
///
/// A MapLibre style is JSON, and this builds it from [LuqmaColors] rather than shipping a
/// file of hex codes. That is the same rule the rest of the product follows — no colour is
/// written in a screen — and here it buys something specific: the map follows the app into
/// dark mode instead of staying a bright rectangle in the middle of a dark screen.
///
/// **There are no text layers, and that is deliberate.** Three reasons, in order of
/// weight. `docs/09` says landmarks are Luqma's own layer drawn on top and that they are
/// "the actual fix for couriers circling" — the basemap is the background, not the
/// information. OSM's coverage of Edku is thin (seven mapped places within eighteen
/// kilometres), so the labels that do exist are sparse enough to look broken rather than
/// helpful. And rendering text at all needs a glyph server: MapLibre fetches `.pbf` font
/// ranges over HTTP, which would put a third party back in the path of a map we host
/// specifically so nobody can switch it off.
///
/// So the basemap is geometry only — water, land, roads, buildings — and every word on
/// the screen is Luqma's own marker, in Arabic, from our own table.
String luqmaMapStyle({
  required LuqmaColors colors,
  required String pmtilesUrl,
  required bool dark,
}) {
  String hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  // Roles rather than swatches. The map has its own contrast problem — a road has to
  // read against the ground it sits on at a glance, from a phone held at arm's length in
  // the street — so these are pulled a step apart from the card palette.
  final ground = hex(colors.background.toARGB32());
  final land = hex(colors.surface.toARGB32());
  final built = hex(colors.hairline.toARGB32());
  final line = hex(colors.border.toARGB32());
  final road = dark
      ? hex(LuqmaPalette.darkSurfaceHigh.toARGB32())
      : hex(LuqmaPalette.white.toARGB32());

  // Named in [LuqmaPalette] rather than written here. Two hex literals sat at this line
  // with a comment explaining why water needs its own colour — which was true, and was
  // not a reason to put a literal in a builder. The explanation justified the *role*; it
  // did not justify skipping the palette.
  final water = hex(
    (dark ? LuqmaPalette.waterDark : LuqmaPalette.water).toARGB32(),
  );

  Map<String, Object> fill(String id, String source, String colour, {
    List<Object>? filter,
    double opacity = 1,
    int? minZoom,
  }) => {
        'id': id,
        'type': 'fill',
        'source': 'protomaps',
        'source-layer': source,
        'filter': ?filter,
        'minzoom': ?minZoom,
        'paint': {'fill-color': colour, 'fill-opacity': opacity},
      };

  Map<String, Object> roadLine(
    String id,
    List<String> kinds,
    List<Object> width, {
    String? colour,
  }) => {
        'id': id,
        'type': 'line',
        'source': 'protomaps',
        'source-layer': 'roads',
        'filter': <Object>['match', <Object>['get', 'kind'], kinds, true, false],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': colour ?? road, 'line-width': width},
      };

  final style = <String, Object>{
    'version': 8,
    'name': 'لقمة — إدكو',
    // Named even though nothing draws text: a style with no glyph source is refused by
    // some MapLibre versions the moment any layer *could* need one, and the empty string
    // is not a valid URL. Pointing it at the source's own name keeps the document valid
    // without reaching for a font server.
    'sources': {
      'protomaps': {
        'type': 'vector',
        'url': 'pmtiles://$pmtilesUrl',
        // ODbL's condition for a produced work, and the reason this map costs nothing.
        // It has to be visible on screen; the widget draws it.
        'attribution': '© OpenStreetMap',
      },
    },
    'layers': <Map<String, Object>>[
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': ground},
      },
      fill('earth', 'earth', ground),
      fill('landcover', 'landcover', land, opacity: dark ? .35 : .55),
      fill('landuse', 'landuse', land, opacity: dark ? .5 : .7),
      fill('water', 'water', water),
      // Buildings arrive late. Before z14 they are a grey wash that hides the streets;
      // after it they are what tells somebody which block they are on.
      fill('buildings', 'buildings', built, opacity: dark ? .55 : .8, minZoom: 14),
      // Three weights, because a courier is looking for the turn rather than the map.
      // The interpolations are on zoom so a road keeps its relative weight while somebody
      // pinches in, instead of every line thickening at once into a solid mass.
      roadLine('roads-minor', ['minor_road', 'other', 'path'], <Object>[
        'interpolate', <Object>['linear'], <Object>['zoom'],
        13, 0.5, 16, 3, 19, 12,
      ]),
      roadLine('roads-medium', ['medium_road'], <Object>[
        'interpolate', <Object>['linear'], <Object>['zoom'],
        11, 0.8, 16, 5, 19, 18,
      ]),
      roadLine('roads-major', ['major_road', 'highway'], <Object>[
        'interpolate', <Object>['linear'], <Object>['zoom'],
        8, 1, 16, 7, 19, 24,
      ], colour: dark ? hex(LuqmaPalette.darkEdge.toARGB32()) : land),
      {
        'id': 'boundaries',
        'type': 'line',
        'source': 'protomaps',
        'source-layer': 'boundaries',
        'paint': {
          'line-color': line,
          'line-width': 1.0,
          'line-dasharray': <Object>[3, 2],
          'line-opacity': 0.6,
        },
      },
    ],
  };

  return jsonEncode(style);
}
