import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// What an app says when its notifications are off.
///
/// Until this existed the permission was asked for in the first seconds of the first
/// launch, with no explanation, and the answer was thrown away — so a merchant who
/// refused it had a phone that never rang and an app that never mentioned it. A quiet
/// evening and a broken alarm looked identical.
void main() {
  Future<void> pump(
    WidgetTester tester,
    LuqmaPushPermission permission, {
    Future<LuqmaPushPermission> Function()? onEnable,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LuqmaTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: LuqmaNotificationBanner(
              reason: 'عشان تعرف أول ما يجيلك أوردر.',
              read: () async => permission,
              request: onEnable ?? () async => permission,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('says nothing at all when alerts are already on', (tester) async {
    await pump(tester, LuqmaPushPermission.granted);

    expect(find.byKey(LuqmaNotificationBanner.bannerKey), findsNothing);
  });

  // A developer's machine and CI have no Firebase, and neither should be told their
  // notifications are broken — nothing is broken, there is nothing to notify.
  testWidgets('and nothing when this build has no push at all', (tester) async {
    await pump(tester, LuqmaPushPermission.unavailable);

    expect(find.byKey(LuqmaNotificationBanner.bannerKey), findsNothing);
  });

  testWidgets('offers to turn them on before Android has ever asked', (tester) async {
    await pump(tester, LuqmaPushPermission.notDetermined);

    expect(find.byKey(LuqmaNotificationBanner.bannerKey), findsOneWidget);
    expect(find.text('عشان تعرف أول ما يجيلك أوردر.'), findsOneWidget);
    expect(find.byKey(LuqmaNotificationBanner.enableKey), findsOneWidget);
  });

  testWidgets('and the banner goes when the answer is yes', (tester) async {
    await pump(
      tester,
      LuqmaPushPermission.notDetermined,
      onEnable: () async => LuqmaPushPermission.granted,
    );

    await tester.tap(find.byKey(LuqmaNotificationBanner.enableKey));
    await tester.pumpAndSettle();

    expect(find.byKey(LuqmaNotificationBanner.bannerKey), findsNothing);
  });

  // The state that has to be a sentence rather than a button: Android shows its dialog
  // once, so asking again does nothing at all and a button offering to is a dead end.
  testWidgets('tells somebody who refused where the switch actually is', (tester) async {
    await pump(tester, LuqmaPushPermission.denied);

    expect(find.byKey(LuqmaNotificationBanner.bannerKey), findsOneWidget);
    expect(find.byKey(LuqmaNotificationBanner.enableKey), findsNothing);
    expect(find.byKey(LuqmaNotificationBanner.settingsPathKey), findsOneWidget);
  });

  testWidgets('a refusal at the dialog turns the offer into that sentence',
      (tester) async {
    await pump(
      tester,
      LuqmaPushPermission.notDetermined,
      onEnable: () async => LuqmaPushPermission.denied,
    );

    await tester.tap(find.byKey(LuqmaNotificationBanner.enableKey));
    await tester.pumpAndSettle();

    expect(find.byKey(LuqmaNotificationBanner.settingsPathKey), findsOneWidget);
  });
}
