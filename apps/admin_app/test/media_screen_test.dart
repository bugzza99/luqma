import 'package:admin_app/src/media/media_controller.dart';
import 'package:admin_app/src/media/media_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Reviewing photos before they reach the storefront.
void main() {
  Media media(String id, {MediaKind kind = MediaKind.menuItem}) => Media(
        id: id,
        kind: kind,
        url: 'https://example.test/$id.webp',
        uploadedBy: 'u1',
        width: 1200,
        height: 900,
      );

  late FakeMediaRepository repository;

  Future<void> pump(
    WidgetTester tester, {
    List<Media> seed = const [],
    Failure? failure,
    Size size = const Size(1080, 2340),
    double devicePixelRatio = 3.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);

    repository = FakeMediaRepository(seed: seed, failure: failure);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaRepositoryProvider.overrideWithValue(repository),
          currentIdentityProvider.overrideWith(
            (ref) => Stream.value(
              const LuqmaIdentity(uid: 'admin1', claims: {'admin': true}),
            ),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MediaScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an empty queue says so rather than showing nothing', (tester) async {
    await pump(tester);
    expect(find.byKey(MediaScreen.emptyKey), findsOneWidget);
  });

  testWidgets('shows what is waiting', (tester) async {
    await pump(tester, seed: [media('m1'), media('m2')]);

    expect(find.byKey(MediaScreen.cardKey('m1')), findsOneWidget);
    expect(find.byKey(MediaScreen.cardKey('m2')), findsOneWidget);
  });

  // A banner is judged on whether it holds its 3:1 shape; a dish photo on whether it
  // looks like food. The reviewer has to know which they are looking at.
  testWidgets('says what each image is for', (tester) async {
    await pump(tester, seed: [media('m1', kind: MediaKind.promotion)]);

    expect(find.text('بانر إعلان'), findsOneWidget);
  });

  testWidgets('approving takes it out of the queue', (tester) async {
    await pump(tester, seed: [media('m1'), media('m2')]);

    await tester.tap(find.byKey(MediaScreen.approveKey('m1')));
    await tester.pumpAndSettle();

    expect(find.byKey(MediaScreen.cardKey('m1')), findsNothing);
    expect(find.byKey(MediaScreen.cardKey('m2')), findsOneWidget);
  });

  testWidgets('rejecting asks for a reason', (tester) async {
    await pump(tester, seed: [media('m1')]);

    await tester.tap(find.byKey(MediaScreen.rejectKey('m1')));
    await tester.pumpAndSettle();

    expect(find.byKey(MediaScreen.reasonFieldKey), findsOneWidget);
  });

  testWidgets('a rejection with a reason is recorded', (tester) async {
    await pump(tester, seed: [media('m1')]);

    await tester.tap(find.byKey(MediaScreen.rejectKey('m1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(MediaScreen.reasonFieldKey), 'الصورة مش واضحة');
    await tester.tap(find.byKey(MediaScreen.confirmRejectKey));
    await tester.pumpAndSettle();

    final stored = (await repository.get('m1')).valueOrNull!;
    expect(stored.status, MediaStatus.rejected);
    expect(stored.reviewNote, 'الصورة مش واضحة');
    expect(stored.reviewedBy, 'admin1', reason: 'who decided is recorded');
  });

  // Being able to refuse without explaining means the merchant re-uploads the same photo.
  testWidgets('a rejection can be sent without one, but is still recorded',
      (tester) async {
    await pump(tester, seed: [media('m1')]);

    await tester.tap(find.byKey(MediaScreen.rejectKey('m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MediaScreen.confirmRejectKey));
    await tester.pumpAndSettle();

    final stored = (await repository.get('m1')).valueOrNull!;
    expect(stored.status, MediaStatus.rejected);
  });

  testWidgets('shows waiting count in header banner', (tester) async {
    await pump(tester, seed: [media('m1'), media('m2')]);

    expect(find.text('صورتان في انتظار المراجعة'), findsOneWidget);
  });

  testWidgets('renders cleanly without overflow on a phone screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;

    await pump(tester, seed: [media('m1')]);

    expect(find.byKey(MediaScreen.cardKey('m1')), findsOneWidget);
    expect(find.byKey(MediaScreen.approveKey('m1')), findsOneWidget);
    expect(find.byKey(MediaScreen.rejectKey('m1')), findsOneWidget);
  });

  group('QA review findings', () {
    testWidgets('hides dimensions line when either width or height is 0',
        (tester) async {
      final zeroDim = Media(
        id: 'zero',
        kind: MediaKind.menuItem,
        url: 'https://example.test/zero.webp',
        width: 0,
        height: 0,
      );
      final normalDim = Media(
        id: 'normal',
        kind: MediaKind.menuItem,
        url: 'https://example.test/normal.webp',
        width: 1200,
        height: 900,
      );

      await pump(tester, seed: [zeroDim, normalDim]);

      expect(find.text('0×0'), findsNothing);
      expect(find.text('1200×900'), findsOneWidget);
    });

    testWidgets('shows context: who uploaded it and when', (tester) async {
      final item = Media(
        id: 'ctx',
        kind: MediaKind.merchantLogo,
        url: 'https://example.test/ctx.webp',
        uploadedBy: '00000000-0000-0000-0000-0000000000e1',
        createdAt: DateTime.now(),
        width: 800,
        height: 800,
      );

      await pump(tester, seed: [item]);

      expect(find.text('لوجو مطعم'), findsOneWidget);
      // The uploader's id is never printed; the server names the person instead.
      expect(find.textContaining('أحمد التاجر'), findsNothing);
      expect(find.textContaining('النهارده'), findsOneWidget);
    });

    testWidgets('tap opens full-screen zoom with InteractiveViewer',
        (tester) async {
      await pump(tester, seed: [media('m1')]);

      // Tap card / image
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byTooltip('إغلاق'), findsOneWidget);

      // Close zoom
      await tester.tap(find.byTooltip('إغلاق'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('reject failure keeps dialog open with user reason and shows error',
        (tester) async {
      await pump(tester, seed: [media('m1')]);
      // The queue loads; only the write that follows fails.
      repository.failure = const OfflineFailure();

      await tester.tap(find.byKey(MediaScreen.rejectKey('m1')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(MediaScreen.reasonFieldKey), 'صورة مظلمة');
      await tester.tap(find.byKey(MediaScreen.confirmRejectKey));
      await tester.pumpAndSettle();

      // Dialog stays open with user's reason
      expect(find.text('صورة مظلمة'), findsOneWidget);
      expect(find.text('فشل رفض الصورة، حاول مرة أخرى'), findsOneWidget);
    });

    testWidgets('approve failure shows error SnackBar and re-enables button',
        (tester) async {
      await pump(tester, seed: [media('m1')]);
      // The queue loads; only the write that follows fails.
      repository.failure = const OfflineFailure();

      await tester.tap(find.byKey(MediaScreen.approveKey('m1')));
      await tester.pumpAndSettle();

      expect(find.text('فشل اعتماد الصورة، حاول مرة أخرى'), findsOneWidget);
      expect(find.byKey(MediaScreen.cardKey('m1')), findsOneWidget);
    });
  });

  // «بواسطة: <uuid>» told nobody anything (QA review 2026-09-19).
  testWidgets('a picture says which shop and which dish it is for', (tester) async {
    await pump(tester, seed: [media('m1')]);
    repository.contexts['m1'] =
        const MediaContext(shop: 'مطعم البحر', item: 'فراخ مشوية', uploader: 'أبو حاتم');
    // The queue re-reads the names when the list changes; this re-asks as it would.
    final container = ProviderScope.containerOf(tester.element(find.byType(MediaScreen)));
    container.invalidate(pendingMediaContextProvider);
    await tester.pumpAndSettle();

    final line = find.byKey(MediaScreen.contextKey('m1'));
    expect(line, findsOneWidget);
    final text = tester.widget<Text>(find.descendant(of: line, matching: find.byType(Text))).data!;
    expect(text, contains('مطعم البحر'));
    expect(text, contains('فراخ مشوية'));
    expect(text, contains('أبو حاتم'));
  });
}
