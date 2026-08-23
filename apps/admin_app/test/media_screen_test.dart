import 'package:admin_app/src/auth/admin_access.dart';
import 'package:admin_app/src/auth/identity_provider.dart';
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

  Future<void> pump(WidgetTester tester, {List<Media> seed = const []}) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    repository = FakeMediaRepository(seed: seed);

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
}
