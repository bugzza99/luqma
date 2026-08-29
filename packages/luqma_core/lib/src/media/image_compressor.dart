import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// What happens to a photo between the camera and the bucket.
///
/// A phone photograph is 3–8 MB. Six hundred menu items at that size is three gigabytes
/// against a one-gigabyte tier — and on a phone in a shop, on Egyptian mobile data,
/// uploading eight megabytes of a plate of fish is a minute of somebody's afternoon per
/// dish. Nothing is uploaded as it was taken.
///
/// The bucket refuses anything over 2 MiB, but that is the backstop for a caller that
/// forgot. This is the thing that means no caller has to remember.
abstract final class ImageCompressor {
  const ImageCompressor._();

  /// The long edge, in pixels.
  ///
  /// A merchant cover is the widest an image is ever drawn, and on the largest phone in
  /// Edku that is under 500 logical pixels — 1600 is three times that, which leaves room
  /// for a tablet and for the crop an admin might want, and nothing beyond it is ever
  /// visible to anybody.
  static const maxEdge = 1600;

  /// JPEG quality. Below about 80 the artefacts start showing on flat areas — a plain
  /// tablecloth is where you see it first — and above 90 the file doubles for a
  /// difference nobody can point at.
  static const quality = 85;

  /// What `storage.buckets` refuses, mirrored here so a test can assert against the same
  /// number the database enforces.
  static const bucketLimitBytes = 2 * 1024 * 1024;

  /// Decodes [bytes], fits it inside [maxEdge], and re-encodes it as JPEG.
  ///
  /// Throws [FormatException] when the bytes are not an image this build can read —
  /// which is what a caller wants to hear, because it is the one failure that is the
  /// person's own doing and can be answered with "pick another picture".
  ///
  /// Never enlarges: upscaling a small picture makes the file bigger and the picture no
  /// better, and a home cook's old phone is exactly where that would happen.
  static Future<Uint8List> shrink(Uint8List bytes) async {
    // The decoder has two ways of saying "this is not an image": it returns null for
    // some inputs, and walks off the end of the buffer for others — four random bytes
    // give a RangeError, not a null. Both are the same fact to whoever is holding the
    // phone, so both leave here as one.
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      throw const FormatException('not a picture this build can read');
    }
    if (decoded == null) {
      throw const FormatException('not a picture this build can read');
    }

    final longEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
    final fitted = longEdge <= maxEdge
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxEdge : null,
            height: decoded.height > decoded.width ? maxEdge : null,
            // The default is nearest-neighbour, which turns a downscaled photograph into
            // a field of speckles wherever there is fine detail — a menu board, a lace
            // tablecloth, the text on a bottle.
            interpolation: img.Interpolation.average,
          );

    return Uint8List.fromList(img.encodeJpg(fitted, quality: quality));
  }
}
