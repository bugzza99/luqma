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
    Failure? setFailure,
    Map<String, Object>? returnedValues,
  }) async {
    config = FakeConfigRepository(
      seed: seed,
      setFailure: setFailure,
      returnedValues: returnedValues,
    );

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

  testWidgets('shows all per-app version and update URL fields', (
    tester,
  ) async {
    await pump(
      tester,
      seed: {
        'min_supported_version': '1.2.0',
        'customer_min_supported_version': '1.3.0',
        'admin_update_url': 'https://updates.example/admin.apk',
      },
    );

    expect(find.textContaining('أقل نسخة مدعومة — العميل'), findsOneWidget);
    expect(find.textContaining('أقل نسخة مدعومة — التاجر'), findsOneWidget);
    expect(find.textContaining('أقل نسخة مدعومة — الأدمن'), findsOneWidget);
    expect(find.textContaining('رابط تحديث تطبيق العميل'), findsOneWidget);
    expect(find.textContaining('رابط تحديث تطبيق التاجر'), findsOneWidget);
    expect(find.textContaining('رابط تحديث تطبيق الأدمن'), findsOneWidget);

    TextField fieldFor(String labelPart) => tester.widget<TextField>(
      find.descendant(
        of: find.ancestor(
          of: find.textContaining(labelPart),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(TextField),
      ),
    );

    expect(fieldFor('أقل نسخة مدعومة — العميل').controller!.text, '1.3.0');
    expect(
      fieldFor('أقل نسخة مدعومة — التاجر').controller!.text,
      '1.2.0',
      reason: 'an absent per-app key shows the legacy effective value',
    );
    expect(
      fieldFor('رابط تحديث تطبيق العميل').controller!.text,
      contains('com.luqma.customer'),
    );
    expect(
      fieldFor('رابط تحديث تطبيق الأدمن').controller!.text,
      'https://updates.example/admin.apk',
    );
  });

  testWidgets('saving writes all six per-app update contract keys', (
    tester,
  ) async {
    await pump(tester);

    await tester.ensureVisible(find.byKey(ConfigScreen.saveKey));
    await tester.tap(find.byKey(ConfigScreen.saveKey));
    await tester.pumpAndSettle();

    expect(config.setCalls, hasLength(1));
    expect(
      config.setCalls.single.keys,
      containsAll(<String>[
        'customer_min_supported_version',
        'merchant_min_supported_version',
        'admin_min_supported_version',
        'customer_update_url',
        'merchant_update_url',
        'admin_update_url',
      ]),
    );
    expect(
      config.setCalls.single.keys,
      isNot(contains('min_supported_version')),
    );
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

  testWidgets('an out-of-range active numeric field is refused', (
    tester,
  ) async {
    await pump(tester);

    final timeoutTile = find.widgetWithText(
      ListTile,
      'مهلة قبول الطلب (دقايق)',
    );
    await tester.enterText(
      find.descendant(of: timeoutTile, matching: find.byType(TextField)),
      '61',
    );
    await tester.ensureVisible(find.byKey(ConfigScreen.saveKey));
    await tester.tap(find.byKey(ConfigScreen.saveKey));
    await tester.pumpAndSettle();

    expect(config.setCalls, isEmpty);
  });

  testWidgets('successful save reflects the server-returned config', (
    tester,
  ) async {
    await pump(
      tester,
      seed: {'support_whatsapp': '010'},
      returnedValues: {'support_whatsapp': '011'},
    );

    await tester.ensureVisible(find.byKey(ConfigScreen.saveKey));
    await tester.tap(find.byKey(ConfigScreen.saveKey));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(ConfigScreen.whatsappKey))
          .controller!
          .text,
      '011',
    );
  });

  testWidgets('server validation failure gets a distinct sentence', (
    tester,
  ) async {
    await pump(tester, setFailure: const ValidationFailure());

    await tester.ensureVisible(find.byKey(ConfigScreen.saveKey));
    await tester.tap(find.byKey(ConfigScreen.saveKey));
    await tester.pumpAndSettle();

    expect(find.text('قيمة غير صحيحة — راجع الخانات.'), findsOneWidget);
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
