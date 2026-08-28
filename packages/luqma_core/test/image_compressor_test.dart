import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:luqma_core/luqma_core.dart';

/// What happens to a photo between the camera and the bucket.
///
/// A phone photograph is 3–8 MB. Six hundred menu items at that size is three gigabytes
/// against a one-gigabyte tier, so nothing is uploaded as it was taken. The bucket
/// refuses anything over 2 MiB, but that is a backstop for a caller that forgot — this
/// is the thing that means no caller has to remember.
void main() {
  /// A JPEG of [width]×[height], noisy enough that it cannot compress to nothing.
  Uint8List photo(int width, int height) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x * y) % 256);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 100));
  }

  group('downscaling', () {
    test('a big photo comes back at the long edge and no larger', () async {
      final result = await ImageCompressor.shrink(photo(4000, 3000));

      final decoded = img.decodeImage(result)!;
      expect(decoded.width, ImageCompressor.maxEdge);
      expect(decoded.height, 1200, reason: 'the shape is kept, not stretched');
    });

    test('a tall photo is measured on its own long edge', () async {
      final result = await ImageCompressor.shrink(photo(1200, 3000));

      final decoded = img.decodeImage(result)!;
      expect(decoded.height, ImageCompressor.maxEdge);
      expect(decoded.width, 640);
    });

    // Upscaling a small picture makes the file bigger and the picture no better.
    test('a small photo is left at its own size', () async {
      final result = await ImageCompressor.shrink(photo(400, 300));

      final decoded = img.decodeImage(result)!;
      expect(decoded.width, 400);
      expect(decoded.height, 300);
    });

    test('the result is comfortably under what the bucket refuses', () async {
      final result = await ImageCompressor.shrink(photo(4000, 3000));

      expect(result.length, lessThan(ImageCompressor.bucketLimitBytes),
          reason: 'the upload must not be refused for size');
      expect(result.length, lessThan(photo(4000, 3000).length),
          reason: 'and it must actually be smaller than what came in');
    });

    // Storage is told `image/jpeg` for every object, so a PNG that stayed a PNG would be
    // served under a type it is not.
    test('whatever went in, a JPEG comes out', () async {
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 50, height: 50)));

      final result = await ImageCompressor.shrink(png);

      expect(img.JpegDecoder().isValidFile(result), isTrue);
    });
  });

  group('what it refuses', () {
    test('bytes that are not a picture at all', () async {
      expect(
        () => ImageCompressor.shrink(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<FormatException>()),
      );
    });

    test('nothing', () async {
      expect(
        () => ImageCompressor.shrink(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
