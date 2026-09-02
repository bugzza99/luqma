import 'package:admin_app/src/config/config_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The control plane, edited from one screen.
void main() {
  late FakeConfigRepository config;

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object> seed = const {},
  }) async {
    config = FakeConfigRepository(seed: seed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [configRepositoryProvider.overrideWithValue(config)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: ConfigScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the current values', (tester) async {
    await pump(
      tester,
      seed: {'marketing_push_per_week': 5, 'otp_enabled': true},
    );

    expect(
      tester
          .widget<TextField>(find.byKey(ConfigScreen.pushKey))
          .controller!
          .text,
      '5',
    );
  });

  testWidgets('unfinished launch controls are visible but cannot be changed', (
    tester,
  ) async {
    await pump(
      tester,
      seed: {'marketing_push_per_week': 3, 'otp_enabled': true},
    );

    final otp = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'تفعيل الـ OTP'),
    );
    final push = tester.widget<TextField>(find.byKey(ConfigScreen.pushKey));

    expect(otp.onChanged, isNull);
    expect(push.enabled, isFalse);
    expect(find.textContaining('غير متاح في الإصدار الحالي'), findsWidgets);
  });

  testWidgets('saving never writes unfinished feature flags', (tester) async {
    await pump(
      tester,
      seed: {
        'marketing_push_per_week': 3,
        'otp_enabled': true,
        'admob_enabled': true,
        'public_comments_enabled': true,
        'online_payment_enabled': true,
      },
    );

    await tester.ensureVisible(find.byKey(ConfigScreen.saveKey));
    await tester.tap(find.byKey(ConfigScreen.saveKey));
    await tester.pumpAndSettle();

    expect(config.setCalls, hasLength(1));
    expect(
      config.setCalls.single.keys,
      isNot(
        containsAll(<String>[
          'marketing_push_per_week',
          'otp_enabled',
          'admob_enabled',
          'public_comments_enabled',
          'online_payment_enabled',
        ]),
      ),
    );
  });

  testWidgets('an invalid active numeric field is refused, not saved', (
    tester,
  ) async {
    await pump(tester);

    final timeoutTile = find.widgetWithText(
      ListTile,
      'مهلة قبول الطلب (دقايق)',
    );
    await tester.enterText(
      find.descendant(of: timeoutTile, matching: find.byType(TextField)),
      'تسعة',
    );
    await tester.ensureVisible(find.byKey(ConfigScreen.saveKey));
    await tester.tap(find.byKey(ConfigScreen.saveKey));
    await tester.pumpAndSettle();

    expect(config.setCalls, isEmpty);
  });

  testWidgets('a failed read shows a way out rather than spinning', (
    tester,
  ) async {
    config = FakeConfigRepository(failure: const OfflineFailure());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [configRepositoryProvider.overrideWithValue(config)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: ConfigScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LuqmaErrorView), findsOneWidget);
  });
}
