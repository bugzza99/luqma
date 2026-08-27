import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:luqma_core/luqma_core.dart';

/// The one control that puts a picture into this product.
///
/// Shared by the menu editor, the daily-meal form, the merchant's own logo and cover,
/// the cuisines editor and حول لقمة — six places, one widget, one door. What it must
/// never become is six pickers that each learned the moderation rule separately.
void main() {
  late FakeMediaRepository media;

  /// A photograph far larger than anything that should reach the bucket.
  Uint8List bigPhoto() {
    final image = img.Image(width: 3000, height: 2000);
    for (var y = 0; y < 2000; y += 1) {
      for (var x = 0; x < 3000; x += 1) {
        image.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x * y) % 256);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 100));
  }

  Future<void> pump(
    WidgetTester tester, {
    required PickImage picker,
    String? url,
    Failure? uploadFails,
    void Function(Media)? onUploaded,
  }) async {
    media = FakeMediaRepository(failure: uploadFails);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(media),
          authServiceProvider.overrideWithValue(
            FakeAuthService(restoring: const LuqmaIdentity(uid: 'u1')),
          ),
          pickImageProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: MediaPicker(
                kind: MediaKind.menuItem,
                url: url,
                name: 'سمك مشوي',
                onUploaded: onUploaded ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers a way to add one when there is none', (tester) async {
    await pump(tester, picker: () async => null);

    expect(find.byKey(MediaPicker.pickKey), findsOneWidget);
  });

  testWidgets('picking uploads, and hands back the media', (tester) async {
    Media? reported;
    await pump(tester,
        picker: () async => bigPhoto(), onUploaded: (m) => reported = m);

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    expect(media.uploads, hasLength(1));
    expect(reported, isNotNull);
    expect(reported!.id, media.uploads.single.id);
  });

  // The whole reason the compressor exists. A picker that uploaded what the camera
  // produced would put three gigabytes of menu into a one-gigabyte tier, and each photo
  // would take a minute of somebody's afternoon on mobile data.
  testWidgets('what reaches the repository has been shrunk first', (tester) async {
    final original = bigPhoto();
    await pump(tester, picker: () async => original);

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    expect(media.uploads.single.bytes, lessThan(original.length));
    expect(media.uploads.single.bytes,
        lessThan(ImageCompressor.bucketLimitBytes),
        reason: 'the bucket would refuse anything larger');
  });

  // Backing out of the gallery is a decision. Answering it with an error is the app
  // apologising for the person's own choice.
  testWidgets('backing out of the picker is not a failure', (tester) async {
    await pump(tester, picker: () async => null);

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    expect(media.uploads, isEmpty);
    expect(find.byKey(MediaPicker.errorKey), findsNothing);
  });

  testWidgets('a failed upload says so and leaves a way to retry', (tester) async {
    await pump(tester,
        picker: () async => bigPhoto(), uploadFails: const OfflineFailure());

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    expect(find.byKey(MediaPicker.errorKey), findsOneWidget);
    expect(find.byKey(MediaPicker.pickKey), findsOneWidget, reason: 'another go');
  });

  // A merchant uploads a photo of their fish, opens CustomerApp, and sees nothing. If
  // the screen does not say why, the next thing they do is upload it again.
  testWidgets('says the picture is waiting to be reviewed', (tester) async {
    await pump(tester, picker: () async => bigPhoto());

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    expect(find.byKey(MediaPicker.pendingKey), findsOneWidget);
  });

  testWidgets('a picture that is not one is refused before any upload',
      (tester) async {
    await pump(tester, picker: () async => Uint8List.fromList([1, 2, 3, 4]));

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    expect(media.uploads, isEmpty, reason: 'nothing was sent');
    expect(find.byKey(MediaPicker.errorKey), findsOneWidget);
  });
}
