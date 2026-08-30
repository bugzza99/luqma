import 'package:customer_app/src/about/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// حول لقمة, as the customer reads it.
void main() {
  Future<RemoteConfigService> service(Map<String, Object> values) async {
    final s = RemoteConfigService(FakeConfigFetcher(values));
    await s.refresh();
    return s;
  }

  late FakeExternalLinks links;

  Future<void> pump(
    WidgetTester tester,
    RemoteConfigService config, {
    bool phoneCanOpenLinks = true,
  }) async {
    links = FakeExternalLinks(answer: phoneCanOpenLinks);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(config),
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
          externalLinksProvider.overrideWithValue(links),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: AboutScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an icon with no link set is not drawn', (tester) async {
    await pump(
      tester,
      await service({'about_facebook': 'https://facebook.com/luqma'}),
    );

    expect(find.byKey(AboutScreen.facebookKey), findsOneWidget);
    expect(find.byKey(AboutScreen.whatsappKey), findsNothing);
    expect(find.byKey(AboutScreen.instagramKey), findsNothing);
  });

  testWidgets('every link that is set is drawn', (tester) async {
    await pump(
      tester,
      await service({
        'about_facebook': 'https://facebook.com/luqma',
        'about_whatsapp': 'https://wa.me/20100000000',
        'about_instagram': 'https://instagram.com/luqma',
      }),
    );

    expect(find.byKey(AboutScreen.facebookKey), findsOneWidget);
    expect(find.byKey(AboutScreen.whatsappKey), findsOneWidget);
    expect(find.byKey(AboutScreen.instagramKey), findsOneWidget);
  });

  testWidgets('the description is shown', (tester) async {
    await pump(
      tester,
      await service({'about_description': 'أكل بيتي على أصوله.'}),
    );

    expect(find.text('أكل بيتي على أصوله.'), findsOneWidget);
  });

  // This screen is the owner's, and only the owner's. The build number was sitting
  // directly under their photo and description with nothing between them — technical
  // detail presented as though it were part of who they are. It lives on حسابي now.
  testWidgets('and the build number is not on it', (tester) async {
    await pump(
      tester,
      await service({'about_description': 'أكل بيتي على أصوله.'}),
    );

    expect(find.textContaining('نسخة'), findsNothing);
  });

  // `launchUrl` fails two ways and this screen ignored both: it returns `false` when
  // nothing on the device handled the URL, and it *throws* when no activity is
  // registered for the scheme at all. A tap that does neither of two things and says
  // nothing reads as a broken button, and the person's next move is to tap it again.
  testWidgets('an icon opens the link the owner set', (tester) async {
    await pump(
      tester,
      await service({'about_facebook': 'https://facebook.com/luqma'}),
    );

    await tester.tap(find.byKey(AboutScreen.facebookKey));
    await tester.pumpAndSettle();

    expect(links.opened.single, Uri.parse('https://facebook.com/luqma'));
  });

  testWidgets('a phone that cannot open it says so', (tester) async {
    await pump(
      tester,
      await service({'about_facebook': 'https://facebook.com/luqma'}),
      phoneCanOpenLinks: false,
    );

    await tester.tap(find.byKey(AboutScreen.facebookKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('فيسبوك'), findsOneWidget);
  });
}
