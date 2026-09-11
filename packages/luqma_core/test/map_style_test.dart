import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The basemap style, which is JSON and therefore unchecked by the compiler.
///
/// Everything in `luqma_map_style.dart` is a string key or a magic layer name that only
/// MapLibre validates, and it validates it on a phone rather than here. So these pin the
/// handful of things that would fail silently: a source name the layers do not reference,
/// a colour written in rather than read from the theme, and a text layer creeping in —
/// which would send MapLibre to a glyph server this product deliberately does not use.
void main() {
  Map<String, dynamic> styleFor(LuqmaColors colors, {bool dark = false}) =>
      jsonDecode(
        luqmaMapStyle(
          colors: colors,
          pmtilesUrl: 'https://example.test/edku.pmtiles',
          dark: dark,
        ),
      ) as Map<String, dynamic>;

  final light = LuqmaColors.light;
  final dark = LuqmaColors.dark;

  // Both themes, here and below. These ran against the light style alone, so anything
  // that broke only in dark mode — the theme half of the product nobody looks at as
  // often — passed unremarked.
  test('every layer names the one source that is declared', () {
    for (final (colors, isDark) in [(light, false), (dark, true)]) {
      final style = styleFor(colors, dark: isDark);
      final sources = (style['sources'] as Map).keys.toSet();
      final layers = (style['layers'] as List).cast<Map<String, dynamic>>();

      expect(sources, hasLength(1), reason: 'one archive, one source');
      for (final layer in layers) {
        // Every drawn layer except `background` reads from the archive; one without a
        // source was skipped entirely by the old filter rather than questioned.
        if (layer['type'] == 'background') continue;
        expect(layer['source'], isNotNull,
            reason: 'layer ${layer['id']} draws from nothing');
        expect(sources, contains(layer['source']),
            reason: 'layer ${layer['id']} points at a source nothing declares, '
                'which renders as a blank map rather than as an error');
      }
    }
  });

  test('the archive is addressed through the pmtiles protocol', () {
    for (final (colors, isDark) in [(light, false), (dark, true)]) {
      final source =
          (styleFor(colors, dark: isDark)['sources'] as Map)['protomaps'] as Map;
      expect(source['url'], startsWith('pmtiles://'));
    }
    final source = (styleFor(light)['sources'] as Map)['protomaps'] as Map;

    // Without the scheme MapLibre treats the url as a TileJSON endpoint and asks for a
    // document that is not there — the map draws the background colour and nothing else.
    expect(source['url'], startsWith('pmtiles://'));
    expect(source['attribution'], contains('OpenStreetMap'),
        reason: "ODbL's condition on a produced work, and the price of this map");
  });

  test('nothing draws text, so nothing reaches for a glyph server', () {
    for (final (colors, isDark) in [(light, false), (dark, true)]) {
      final style = styleFor(colors, dark: isDark);
      final layers = (style['layers'] as List).cast<Map<String, dynamic>>();

      // The root key first. The layers were checked and this was not — and a `glyphs`
      // url is precisely the thing that would fetch fonts, whether or not a layer uses
      // it yet.
      expect(style.containsKey('glyphs'), isFalse,
          reason: 'a glyphs source is a font server in the path of the map');

      expect(layers.map((l) => l['type']), isNot(contains('symbol')));
      for (final layer in layers) {
        final layout = layer['layout'] as Map?;
        expect(layout?.containsKey('text-field') ?? false, isFalse,
            reason: 'layer ${layer['id']} would need fonts fetched over HTTP');
      }
    }
  });

  // The point of building the style in Dart rather than shipping a JSON file: a map that
  // stayed bright inside a dark app would be the one rectangle on screen that ignored the
  // theme, and it would do it silently.
  //
  // This asserted only that light and dark differ, which two hardcoded colours satisfy
  // just as well as two tokens — so it passed in exactly the case it existed to catch.
  // It reads the token now, so the test fails if the lookup is replaced by a literal.
  test('the ground is the theme token, not a colour chosen here', () {
    String ground(Map<String, dynamic> style) =>
        (((style['layers'] as List).first as Map)['paint']
            as Map)['background-color'] as String;

    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

    expect(ground(styleFor(light)), hex(light.background));
    expect(ground(styleFor(dark, dark: true)), hex(dark.background));
  });

  // Same trap, and the one the reviewer found first: water was two hex literals under a
  // comment explaining why water needs its own colour. The explanation justified the
  // role; it did not justify skipping the palette.
  test('water is the palette swatch, not a literal in the builder', () {
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    String water(Map<String, dynamic> style) =>
        ((((style['layers'] as List).cast<Map<String, dynamic>>())
                    .firstWhere((l) => l['id'] == 'water')['paint'])
                as Map)['fill-color'] as String;

    expect(water(styleFor(light)), hex(LuqmaPalette.water));
    expect(water(styleFor(dark, dark: true)), hex(LuqmaPalette.waterDark));
  });

  test('water stays distinct from the land it borders, in both themes', () {
    for (final (colors, isDark) in [(light, false), (dark, true)]) {
      final layers =
          (styleFor(colors, dark: isDark)['layers'] as List).cast<Map<String, dynamic>>();
      final water = layers.firstWhere((l) => l['id'] == 'water');
      final earth = layers.firstWhere((l) => l['id'] == 'earth');

      // Edku sits between the sea and a lake, so the shoreline is the most useful
      // landmark on the map. Water reading as land would erase it.
      expect((water['paint'] as Map)['fill-color'],
          isNot((earth['paint'] as Map)['fill-color']));
    }
  });

  /// Whether any of it can actually be seen.
  ///
  /// The style had layers for roads, buildings and water throughout, and the archive has
  /// the geometry — a tile over the middle of Edku carries 87 roads and 77 buildings. It
  /// read as an empty beige rectangle on a real phone because **every feature was painted
  /// within a hair of the ground it sat on**: roads white on cream at 1.17:1, the widest
  /// roads at 1.24:1, and buildings in `hairline`, which the palette file itself labels
  /// decorative-only at 1.5:1 and says a meaningful boundary needs 3:1.
  ///
  /// `isNot(...)` above is what let that through: two colours that differ by nothing
  /// visible are still two different strings. These ask the question in the unit the eye
  /// uses.
  group('the map can be read', () {
    // WCAG's relative luminance and contrast ratio, which is what every other colour
    // decision in this product is argued in.
    double luminance(String hex) {
      final v = int.parse(hex.substring(1), radix: 16);
      double channel(int c) {
        final s = c / 255;
        return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
      }
      return 0.2126 * channel((v >> 16) & 0xFF) +
          0.7152 * channel((v >> 8) & 0xFF) +
          0.0722 * (channel(v & 0xFF));
    }

    double contrast(String a, String b) {
      final (x, y) = (luminance(a), luminance(b));
      final (hi, lo) = x > y ? (x, y) : (y, x);
      return (hi + 0.05) / (lo + 0.05);
    }

    String ground(List<Map<String, dynamic>> layers) =>
        ((layers.firstWhere((l) => l['id'] == 'background')['paint']) as Map)
            ['background-color'] as String;

    // 3:1, the ratio this palette already cites for a boundary that means something, and
    // the ratio WCAG asks of a non-text graphic. A line thin enough to be a road on a
    // phone held at arm-s length needs at least that.
    test('every line on it clears 3:1 against the ground', () {
      for (final (colors, isDark) in [(light, false), (dark, true)]) {
        final layers =
            (styleFor(colors, dark: isDark)['layers'] as List).cast<Map<String, dynamic>>();
        final under = ground(layers);

        final lines = layers.where((l) => l['type'] == 'line');
        expect(lines, isNotEmpty);
        for (final layer in lines) {
          final colour = (layer['paint'] as Map)['line-color'] as String;
          expect(contrast(colour, under), greaterThanOrEqualTo(3.0),
              reason: 'layer ${layer['id']} is drawn at '
                  '${contrast(colour, under).toStringAsFixed(2)}:1 on the ground in '
                  '${isDark ? 'dark' : 'light'}, which is a line nobody can see');
        }
      }
    });

    // A block of buildings is what tells somebody which street they are on once they are
    // close in, and a fill alone cannot carry that at a subtle tone. The outline is the
    // part that has to be visible, which the loop above now checks.
    test('buildings are drawn with an outline, not a wash alone', () {
      for (final (colors, isDark) in [(light, false), (dark, true)]) {
        final layers =
            (styleFor(colors, dark: isDark)['layers'] as List).cast<Map<String, dynamic>>();
        final buildings =
            layers.where((l) => (l['id'] as String).startsWith('buildings'));

        expect(buildings.map((l) => l['type']), containsAll(['fill', 'line']));
      }
    });

    // A large field of colour reads at a lower ratio than a line does, so this floor is
    // lower on purpose — but 1.3:1 is not a shoreline, it is a slightly different beige.
    test('water reads as water beside the land', () {
      for (final (colors, isDark) in [(light, false), (dark, true)]) {
        final layers =
            (styleFor(colors, dark: isDark)['layers'] as List).cast<Map<String, dynamic>>();
        final water =
            ((layers.firstWhere((l) => l['id'] == 'water')['paint']) as Map)
                ['fill-color'] as String;

        expect(contrast(water, ground(layers)), greaterThanOrEqualTo(1.6),
            reason: 'the shoreline is the most useful landmark in this city');
      }
    });
  });
}
