import 'package:customer_app/src/developer/developer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// عن المطور, as the customer reads it — the person, on a page of their own.
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
            child: DeveloperScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('draws the name and the bio that are set', (tester) async {
    await pump(
      tester,
      await service({'developer_name': 'محمد رمضان', 'developer_bio': 'من إدكو.'}),
    );

    expect(find.byKey(DeveloperScreen.nameKey), findsOneWidget);
    expect(find.text('من إدكو.'), findsOneWidget);
  });

  // A blank where a name belongs reads as a screen that failed to load.
  testWidgets('draws no empty name or bio', (tester) async {
    await pump(tester, await service({}));

    expect(find.byKey(DeveloperScreen.nameKey), findsNothing);
    expect(find.byKey(DeveloperScreen.bioKey), findsNothing);
  });

  testWidgets('an icon with no link set is not drawn', (tester) async {
    await pump(
      tester,
      await service({'developer_facebook': 'https://facebook.com/me'}),
    );

    expect(find.byKey(DeveloperScreen.facebookKey), findsOneWidget);
    expect(find.byKey(DeveloperScreen.whatsappKey), findsNothing);
    expect(find.byKey(DeveloperScreen.instagramKey), findsNothing);
  });

  // It reads the developer keys, not the old about ones — those are left in config after
  // the split and must not leak back onto either page.
  testWidgets('reads the developer keys, not the old about ones', (tester) async {
    await pump(
      tester,
      await service({'about_facebook': 'https://facebook.com/old'}),
    );

    expect(find.byKey(DeveloperScreen.facebookKey), findsNothing);
  });

  testWidgets('an icon opens the link that was set', (tester) async {
    await pump(
      tester,
      await service({'developer_facebook': 'https://facebook.com/me'}),
    );

    await tester.tap(find.byKey(DeveloperScreen.facebookKey));
    await tester.pumpAndSettle();

    expect(links.opened.single, Uri.parse('https://facebook.com/me'));
  });

  testWidgets('a phone that cannot open it says so', (tester) async {
    await pump(
      tester,
      await service({'developer_facebook': 'https://facebook.com/me'}),
      phoneCanOpenLinks: false,
    );

    await tester.tap(find.byKey(DeveloperScreen.facebookKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('فيسبوك'), findsOneWidget);
  });
}
