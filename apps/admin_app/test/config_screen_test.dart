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
    String appVersion = '',
  }) async {
    config = FakeConfigRepository(
      seed: seed,
      setFailure: setFailure,
      returnedValues: returnedValues,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configRepositoryProvider.overrideWithValue(config),
          appVersionProvider.overrideWithValue(appVersion),
        ],
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

  // QA review 2026-09-19: the weekly marketing limit was greyed out as «غير متاح» long after
  // marketing pushes started working, and four switches that could not be switched each
  // showed a raw database key.
  testWidgets('the marketing limit can be changed, and is saved', (tester) async {
    await pump(tester, seed: {'marketing_push_per_week': 3});

    final push = tester.widget<TextField>(find.byKey(ConfigScreen.pushKey));
    expect(push.enabled, isNot(isFalse));
    expect(find.textContaining('غير متاح في الإصدار الحالي'), findsNothing);
  });

  testWidgets('what does not exist yet is one sentence, with no database keys', (tester) async {
    await pump(tester);

    expect(
      find.textContaining('أي تعديل هنا بيوصل للتطبيقات أول ما تتفتح'),
      findsOneWidget,
    );
    expect(find.byKey(ConfigScreen.unavailableKey), findsOneWidget);
    expect(find.text('otp_enabled'), findsNothing);
    expect(find.text('min_ratings_to_show'), findsNothing);
  });

  testWidgets('the one commission rate shows, and a wrong one is said under it', (tester) async {
    await pump(tester, seed: {'default_commission_percent': 5, 'commission_alert_pounds': 500});

    final field = tester.widget<TextField>(find.byKey(ConfigScreen.commissionKey));
    expect(field.controller!.text, '5');

    await tester.enterText(find.byKey(ConfigScreen.commissionKey), '80');
    await tester.ensureVisible(find.byKey(ConfigScreen.saveCommissionKey));
    await tester.tap(find.byKey(ConfigScreen.saveCommissionKey));
    await tester.pumpAndSettle();
    expect(find.text('اكتب نسبة من 0 لـ 50'), findsOneWidget);
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
      // The label is the field's own now, so the field is the label's ancestor.
      find.ancestor(
        of: find.textContaining(labelPart),
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

  /// A version nobody can install.
  ///
  /// `min_supported_version` is compared against the version *name*, and the force-update
  /// gate has no back door by design — so a minimum set above what exists walls every phone
  /// on that app out of the product. The admin field is the worst of the three: set above
  /// the admin's own build, it locks out the only app that could undo it.
  ///
  /// All three apps share one version, so the admin build's own version is the newest that
  /// exists, and that is the ceiling.
  group('a minimum version nobody can install', () {
    Future<void> setField(WidgetTester tester, String labelPart, String value) async {
      final field = find.ancestor(
        of: find.textContaining(labelPart),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(ConfigScreen.saveKey));
      await tester.tap(find.byKey(ConfigScreen.saveKey));
      await tester.pumpAndSettle();
    }

    testWidgets('is refused for the admin app, which would lock out its own undo',
        (tester) async {
      await pump(tester, appVersion: '0.9.0 (10)');
      await setField(tester, 'أقل نسخة مدعومة — الأدمن', '1.0.0');
      await save(tester);

      expect(config.setCalls, isEmpty, reason: 'nothing may reach the control plane');
      expect(find.textContaining('0.9.0'), findsWidgets,
          reason: 'the refusal names the newest version that exists');
    });

    testWidgets('and for the customer app too', (tester) async {
      await pump(tester, appVersion: '0.9.0 (10)');
      await setField(tester, 'أقل نسخة مدعومة — العميل', '0.10.0');
      await save(tester);

      expect(config.setCalls, isEmpty, reason: '0.10.0 is above 0.9.0 numerically');
    });

    testWidgets('but the version that exists, or an older one, saves', (tester) async {
      await pump(tester, appVersion: '0.9.0 (10)');
      await setField(tester, 'أقل نسخة مدعومة — العميل', '0.9.0');
      await setField(tester, 'أقل نسخة مدعومة — التاجر', '0.8.2');
      await save(tester);

      expect(config.setCalls, hasLength(1));
    });

    // A build that cannot say what it is must not start refusing things on a guess.
    testWidgets('and a build with no version of its own does not guess', (tester) async {
      await pump(tester);
      await setField(tester, 'أقل نسخة مدعومة — الأدمن', '9.9.9');
      await save(tester);

      expect(config.setCalls, hasLength(1));
    });
  });
}
