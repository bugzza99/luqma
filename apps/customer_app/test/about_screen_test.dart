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

  Future<void> pump(WidgetTester tester, RemoteConfigService config) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteConfigServiceProvider.overrideWithValue(config),
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
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

  testWidgets('the description and version are shown', (tester) async {
    await pump(
      tester,
      await service({'about_description': 'أكل بيتي على أصوله.'}),
    );

    expect(find.text('أكل بيتي على أصوله.'), findsOneWidget);
    expect(find.byKey(AboutScreen.versionKey), findsOneWidget);
    expect(find.textContaining(kLuqmaVersion), findsOneWidget);
  });
}
