import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:luqma_core/luqma_core.dart';

/// Asks for a picture from the gallery, or null when the person backed out.
///
/// Null is not an error. Somebody who opens the gallery and changes their mind has made
/// a decision, and an app that answers it with a red banner is apologising for it.
///
/// This is the only file in this app that knows `image_picker` exists. Everything above
/// it takes a [PickImage], which is why `MediaPicker` — the widget that does the picking,
/// the shrinking and the uploading — is tested with no device, no gallery and no
/// permission prompt.
///
/// `ImageCompressor` is still the one policy for what reaches the bucket. The limit is
/// passed down to the platform too, and it is the same constant rather than a second
/// number: the phone's own decoder brings a twelve-megapixel photograph down to that
/// edge in native code before a byte reaches Dart, where decoding it in full was
/// seconds of work and hundreds of megabytes on the cheapest handsets in town (E6).
Future<Uint8List?> pickImageFromGallery() async {
  const edge = ImageCompressor.maxEdge * 1.0;
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: edge,
    maxHeight: edge,
    // Above what the compressor re-encodes at, so the second pass is the one that counts.
    imageQuality: 95,
  );
  if (picked == null) return null;
  return picked.readAsBytes();
}
