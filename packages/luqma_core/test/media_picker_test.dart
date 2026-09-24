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
    MediaKind kind = MediaKind.menuItem,
    String? url,
    Failure? uploadFails,
    void Function(Media)? onUploaded,
    bool asAdmin = false,
    ShrinkImage? shrink,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    media = FakeMediaRepository(failure: uploadFails);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(media),
          authServiceProvider.overrideWithValue(
            FakeAuthService(restoring: const LuqmaIdentity(uid: 'u1')),
          ),
          pickImageProvider.overrideWithValue(picker),
          // A widget test cannot wait on a real isolate, so it shrinks in the foreground.
          shrinkImageProvider.overrideWithValue(shrink ?? ImageCompressor.shrink),
          if (asAdmin) uploadsArriveApprovedProvider.overrideWithValue(true),
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
                kind: kind,
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

  // E6. The screen shrinks through the provider, whose real value runs off the thread
  // that draws the screen; calling the compressor directly froze the app for seconds on
  // every twelve-megapixel photograph.
  testWidgets('shrinks through the seam that runs in the background', (tester) async {
    var asked = 0;
    await pump(tester, picker: () async => bigPhoto(),
        shrink: (bytes, {maxEdge = ImageCompressor.maxEdge,
            quality = ImageCompressor.quality}) {
      if (maxEdge == ImageCompressor.maxEdge) asked++;
      return ImageCompressor.shrink(bytes, maxEdge: maxEdge, quality: quality);
    });

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(media.uploads, hasLength(1));
  });

  test('the real seam is the background one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(shrinkImageProvider), ImageCompressor.shrinkInBackground);
  });

  // A thumbnail used to download the whole 1600px photograph. The small copy goes up
  // beside it and is what lists and thumbnails draw (20261101340000).
  testWidgets('a small copy goes up with the photograph', (tester) async {
    await pump(tester, picker: () async => bigPhoto());

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    final uploaded = media.uploads.single;
    final small = img.decodeImage(media.smallCopies[uploaded.id]!)!;
    expect(small.width, ImageCompressor.smallEdge);
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

  group('MediaKind aspect ratios and recommended dimensions', () {
    test('every kind has its documented display aspect ratio', () {
      expect(MediaKind.merchantCover.aspectRatio, closeTo(16 / 9, 0.001));
      expect(MediaKind.merchantLogo.aspectRatio, 1.0);
      expect(MediaKind.menuItem.aspectRatio, 1.0);
      expect(MediaKind.dailyMeal.aspectRatio, 1.0);
      expect(MediaKind.promotion.aspectRatio, Sizes.bannerAspect);
      expect(MediaKind.aboutPhoto.aspectRatio, 1.0);
      expect(MediaKind.cuisine.aspectRatio, 1.0);
    });

    test('every kind has its documented recommended dimensions (max edge <= 1600)', () {
      expect(MediaKind.merchantCover.recommendedDimensions, (width: 1600, height: 900));
      expect(MediaKind.merchantLogo.recommendedDimensions, (width: 800, height: 800));
      expect(MediaKind.menuItem.recommendedDimensions, (width: 1200, height: 1200));
      expect(MediaKind.dailyMeal.recommendedDimensions, (width: 1200, height: 1200));
      expect(MediaKind.promotion.recommendedDimensions, (width: 1600, height: 533));
      expect(MediaKind.aboutPhoto.recommendedDimensions, (width: 800, height: 800));
      expect(MediaKind.cuisine.recommendedDimensions, (width: 800, height: 800));
    });
  });

  group('MediaPicker hint and preview layout', () {
    testWidgets('shows recommended dimensions hint line with Western digits', (tester) async {
      await pump(tester, picker: () async => null, kind: MediaKind.merchantCover);

      expect(find.text('المقاس المناسب: 1600 × 900'), findsOneWidget);
      expect(find.byKey(MediaPicker.hintKey), findsOneWidget);
    });

    testWidgets('logo preview is square and sized like a logo, not stretched to card width', (tester) async {
      await pump(tester, picker: () async => null, kind: MediaKind.merchantLogo);

      expect(find.text('المقاس المناسب: 800 × 800'), findsOneWidget);

      final imageFinder = find.byType(LuqmaImage);
      expect(imageFinder, findsOneWidget);
      final size = tester.getSize(imageFinder);
      expect(size.width, 96.0);
      expect(size.height, 96.0);
      expect(size.width, lessThan(350.0), reason: 'must not stretch full card width');
    });

    testWidgets('cover preview uses 16:9 aspect ratio across width', (tester) async {
      await pump(tester, picker: () async => null, kind: MediaKind.merchantCover);

      final imageFinder = find.byType(LuqmaImage);
      expect(imageFinder, findsOneWidget);
      final size = tester.getSize(imageFinder);
      expect(size.width / size.height, closeTo(16 / 9, 0.02));
    });
  });

  // The moderation card printed «0 × 0» for every picture (QA review 2026-09-19).
  testWidgets('the upload carries the size of the picture that was stored', (tester) async {
    await pump(tester, picker: () async => bigPhoto());

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    // 3000 × 2000 fitted inside the 1600 long edge.
    expect(media.uploads.single.width, ImageCompressor.maxEdge);
    expect(media.uploads.single.height, 1067);
  });

  testWidgets('an ordinary upload waits for review', (tester) async {
    await pump(tester, picker: () async => bigPhoto());

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    expect(media.uploads.single.status, MediaStatus.pending);
  });

  // AdminApp promised «صورك بتظهر على طول» while its uploads sat in the queue.
  testWidgets('in AdminApp an upload arrives approved', (tester) async {
    await pump(tester, picker: () async => bigPhoto(), asAdmin: true);

    await tester.tap(find.byKey(MediaPicker.pickKey));
    await tester.pumpAndSettle();

    expect(media.uploads.single.status, MediaStatus.approved);
  });
}
