import 'dart:typed_data';

/// Where a picture comes from before anything is done to it.
///
/// Returns null when the person backed out of the picker. That is a decision, not a
/// failure — an app that answers "I changed my mind" with a red banner is apologising
/// for somebody's choice.
///
/// A function rather than a class because there is exactly one thing to do, and a seam
/// rather than a direct call because `image_picker` is a platform plugin: it needs a
/// device, a FileProvider entry in the manifest, and on some Androids a camera
/// permission. CustomerApp uploads nothing, so it should carry none of that — and the
/// widget above this line is testable with a function that returns bytes.
///
/// The concrete implementation lives in MerchantApp and AdminApp, which is why those two
/// override [pickImageProvider] in `main` and CustomerApp does not.
typedef PickImage = Future<Uint8List?> Function();

/// What is done to a picture before it is sent: `ImageCompressor.shrinkInBackground` in
/// the apps, and the foreground `ImageCompressor.shrink` in a widget test, which cannot
/// wait on a real isolate.
typedef ShrinkImage = Future<Uint8List> Function(Uint8List bytes);
