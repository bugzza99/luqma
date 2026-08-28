import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

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
/// No resizing here on purpose: `ImageCompressor` does that, in one place, for every
/// caller. A picker that shrank on its own would be a second policy nobody could find.
Future<Uint8List?> pickImageFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  return picked.readAsBytes();
}
