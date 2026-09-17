import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// What the map draws, tested where it can be tested.
///
/// The style declares no glyph source — a hosted Arabic font is the one dependency this
/// basemap exists to avoid — so a landmark's name cannot be a `textField` on a symbol
/// layer. It is painted into the marker's own bitmap instead, which keeps it welded to
/// the coordinate through a pan and needs nothing served.
///
/// That painting is pure Dart and is therefore provable here. The half after it is the
/// plugin's: a widget test has no native view, and a double that drives
/// `MapLibreMapController` asserts against MapLibre's internals rather than against this
/// product. One was written and it hung inside the plugin's own `addSymbol` — a failure
/// that says nothing about whether a customer can read «صيدلية النور» off a pin.
void main() {
  Future<ui.Image> decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  testWidgets('a landmark name is painted into its own pin', (tester) async {
    await tester.runAsync(() async {
      final bare = await decode(await LuqmaMap.pinForTest(LuqmaColors.light.brand));
      final labelled = await decode(await LuqmaMap.labelledPinForTest(
        const LuqmaMapMarker(
          id: 'place',
          lat: 31.30,
          lng: 30.29,
          label: 'صيدلية النور',
        ),
        LuqmaColors.light,
        TextScaler.noScaling,
      ));

      expect(labelled.width, greaterThan(bare.width),
          reason: 'the name is not in the bitmap');
      // A labelled marker **replaces** the bare pin rather than sitting on top of one:
      // it points with a small tick instead of the 48-point teardrop, so a row of named
      // places does not become a wall.
      //
      // This said `lessThan(bare.height)` — 48, a number that happened to be true while
      // the name was set in the 12sp caption token. Raising it to body made the chip two
      // points taller than the teardrop and failed a test about something else entirely.
      // The property is that the label is not stacked on a whole pin, so that is what is
      // measured: a stacked one would be the chip plus another 48.
      expect(labelled.height, lessThan(bare.height * 1.2),
          reason: 'a name stacked on a whole teardrop would be half as tall again, '
              'and twenty-seven of those in a strip is a wall');

      bare.dispose();
      labelled.dispose();
    });
  });

  testWidgets('the name is actually inked, not just measured', (tester) async {
    await tester.runAsync(() async {
      final image = await decode(await LuqmaMap.labelledPinForTest(
        const LuqmaMapMarker(
          id: 'place',
          lat: 31.30,
          lng: 30.29,
          label: 'صيدلية النور',
        ),
        LuqmaColors.light,
        TextScaler.noScaling,
      ));
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;

      // Counted against the card colour the label is drawn on. Measuring the bitmap's
      // *size* is not enough and the first version of this test made exactly that
      // mistake: the box is laid out from the `TextPainter`'s metrics, so it keeps its
      // width and height whether or not a single glyph is ever painted into it. Deleting
      // the `text.paint` call left every dimension assertion green.
      final card = LuqmaColors.light.card;
      var ink = 0;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        final a = data.getUint8(i + 3);
        if (a == 0) continue;
        final differs = (data.getUint8(i) - (card.r * 255).round()).abs() > 24 ||
            (data.getUint8(i + 1) - (card.g * 255).round()).abs() > 24 ||
            (data.getUint8(i + 2) - (card.b * 255).round()).abs() > 24;
        if (differs) ink++;
      }
      // A blank card plus the pointer tick alone leaves very little; Arabic at 12sp
      // leaves a great deal more. The threshold sits far above the tick and far below
      // the glyphs, so it is not a number that has to be re-tuned.
      expect(ink, greaterThan(200),
          reason: 'the label is an empty box — the name was never painted');

      image.dispose();
    });
  });

  testWidgets('a longer name makes a wider pin', (tester) async {
    await tester.runAsync(() async {
      Future<int> widthOf(String label) async {
        final image = await decode(await LuqmaMap.labelledPinForTest(
          LuqmaMapMarker(id: 'x', lat: 31.30, lng: 30.29, label: label),
          LuqmaColors.light,
          TextScaler.noScaling,
        ));
        final width = image.width;
        image.dispose();
        return width;
      }

      // Proves the text is measured rather than drawn into a fixed box, which is what
      // decides whether a long landmark name is legible or clipped. Breaks if the width
      // becomes a constant.
      expect(await widthOf('الفرن البلدي على الترعة'),
          greaterThan(await widthOf('الفرن')));
    });
  });

  testWidgets('the name is scaled with the reader, not fixed', (tester) async {
    await tester.runAsync(() async {
      Future<int> heightAt(TextScaler scaler) async {
        final image = await decode(await LuqmaMap.labelledPinForTest(
          const LuqmaMapMarker(
            id: 'x',
            lat: 31.30,
            lng: 30.29,
            label: 'مسجد الفتح',
          ),
          LuqmaColors.light,
          scaler,
        ));
        final height = image.height;
        image.dispose();
        return height;
      }

      // A bitmap label cannot be resized by the system the way a `Text` can, so if the
      // scaler is not read at paint time somebody who has turned their type up gets a
      // map whose names alone stayed small. Breaks if `textScaler` is dropped from
      // `_labelledPin`.
      expect(await heightAt(const TextScaler.linear(2)),
          greaterThan(await heightAt(TextScaler.noScaling)));
    });
  });

  /// Why the name was unreadable on a real phone.
  ///
  /// The bitmap was painted at **logical** pixels and the renderer places it at
  /// **device** pixels. `MapLibreMapController.java` decodes the bytes with
  /// `inScaled = false` and both densities zeroed, then calls `addImage` with no pixel
  /// ratio — so a 120-pixel-wide PNG occupies 120 device pixels, which on a 2.75x handset
  /// is 44 logical points. A 12sp label arrives at roughly four.
  ///
  /// Nothing about it looked wrong in a test: every existing assertion here is a
  /// comparison between two bitmaps, and both shrank by the same factor.
  testWidgets('the pin is rasterised for the screen it lands on', (tester) async {
    await tester.runAsync(() async {
      Future<(int, int)> sizeAt(double ratio) async {
        final image = await decode(await LuqmaMap.labelledPinForTest(
          const LuqmaMapMarker(
            id: 'x',
            lat: 31.30,
            lng: 30.29,
            label: 'مسجد الفتح',
          ),
          LuqmaColors.light,
          TextScaler.noScaling,
          pixelRatio: ratio,
        ));
        final size = (image.width, image.height);
        image.dispose();
        return size;
      }

      final (w1, h1) = await sizeAt(1);
      final (w3, h3) = await sizeAt(3);

      // Three times the pixels in each direction, within a pixel of rounding. Not merely
      // "bigger": a label that grew by less than the ratio still arrives smaller than it
      // was drawn.
      expect(w3, closeTo(w1 * 3, 3));
      expect(h3, closeTo(h1 * 3, 3));
    });

    await tester.runAsync(() async {
      final bare = await decode(await LuqmaMap.pinForTest(
        LuqmaColors.light.brand,
        pixelRatio: 3,
      ));
      final logical = await decode(await LuqmaMap.pinForTest(LuqmaColors.light.brand));

      // The plain pin is the touch target for choosing an address, so it has the same
      // problem and needs the same answer.
      expect(bare.width, closeTo(logical.width * 3, 3));

      bare.dispose();
      logical.dispose();
    });
  });

  // 12sp was the smallest token in the product, chosen when the label was the only thing
  // on the bitmap rather than something to be read at arm's length on a moving map.
  testWidgets('a landmark name is set at readable body size', (tester) async {
    await tester.runAsync(() async {
      final image = await decode(await LuqmaMap.labelledPinForTest(
        const LuqmaMapMarker(id: 'x', lat: 31.30, lng: 30.29, label: 'مسجد الفتح'),
        LuqmaColors.light,
        TextScaler.noScaling,
      ));
      final painter = TextPainter(
        text: TextSpan(text: 'مسجد الفتح', style: LuqmaType.body),
        textDirection: TextDirection.rtl,
      )..layout();

      // Measured against the body token rather than against a pixel count, so raising the
      // type scale moves both together instead of failing this.
      expect(image.height, greaterThanOrEqualTo(painter.height));

      painter.dispose();
      image.dispose();
    });
  });
}
