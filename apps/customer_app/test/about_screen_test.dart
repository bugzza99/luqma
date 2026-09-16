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

  testWidgets('the description is shown', (tester) async {
    await pump(
      tester,
      await service({'about_description': 'أكل بيتي على أصوله.'}),
    );

    expect(find.text('أكل بيتي على أصوله.'), findsOneWidget);
  });

  testWidgets('and the build number is not on it', (tester) async {
    await pump(
      tester,
      await service({'about_description': 'أكل بيتي على أصوله.'}),
    );

    expect(find.textContaining('نسخة'), findsNothing);
  });

  // The split the owner asked for. The page used to carry their photo in place of the
  // logo and their personal links under the description — «حول لقمة» read as a biography.
  // Even with the old keys still set in config, none of it may come back here.
  testWidgets('is about the product, and carries nothing of the developer', (tester) async {
    await pump(
      tester,
      await service({
        'about_description': 'أكل بيتي على أصوله.',
        'about_facebook': 'https://facebook.com/owner',
        'developer_name': 'محمد',
        'developer_facebook': 'https://facebook.com/owner',
      }),
    );

    expect(find.byType(LuqmaLockup), findsOneWidget);
    expect(find.text('محمد'), findsNothing);
    expect(find.byTooltip('فيسبوك'), findsNothing);
  });

  testWidgets('offers the support number when there is one, and nothing when there is not',
      (tester) async {
    await pump(tester, await service({'support_whatsapp': '01000000000'}));
    expect(find.byKey(AboutScreen.contactKey), findsOneWidget);

    await pump(tester, await service({}));
    expect(find.byKey(AboutScreen.contactKey), findsNothing);
  });
}
