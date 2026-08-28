import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The one thing every screen in all three apps shows when a stream fails.
///
/// It lived as a private `_Error` copied into seventeen files, which had already drifted
/// into fifteen different versions of the same idea — and not one of them offered a way
/// out. On the merchant's order inbox that meant the only recovery from a dropped
/// connection was to kill the app from the task switcher, on the one screen where a lost
/// evening is lost money.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    Object? failure,
    VoidCallback? onRetry,
    bool compact = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: LuqmaTheme.light,
        locale: const Locale('ar'),
        localizationsDelegates: LuqmaStrings.localizationsDelegates,
        supportedLocales: LuqmaStrings.supportedLocales,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: LuqmaErrorView(
              failure: failure ?? const OfflineFailure(),
              onRetry: onRetry,
              compact: compact,
            ),
          ),
        ),
      ),
    );
  }

  group('what it says', () {
    // Three different sentences, because they are three different problems and only one
    // of them is worth trying again straight away.
    testWidgets('offline says the connection failed, not that something broke',
        (tester) async {
      await pump(tester, failure: const OfflineFailure());

      expect(find.text('مفيش اتصال بالإنترنت — الطلب مااتبعتش'), findsOneWidget);
    });

    testWidgets('a refusal says it is not allowed', (tester) async {
      await pump(tester, failure: const PermissionFailure());

      expect(find.text('مش مسموح بالعملية دي'), findsOneWidget);
    });

    testWidgets('anything else falls back rather than showing a stack trace',
        (tester) async {
      await pump(tester, failure: StateError('boom'));

      expect(find.text('حصل خطأ — جرّب تاني'), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
    });

    testWidgets('a missing thing says so', (tester) async {
      await pump(tester, failure: const NotFoundFailure());

      expect(find.text('الحاجة دي مابقتش موجودة'), findsOneWidget);
    });
  });

  group('getting out of it', () {
    testWidgets('offers a way to try again', (tester) async {
      await pump(tester, onRetry: () {});

      expect(find.text('حاول تاني'), findsOneWidget);
    });

    testWidgets('trying again calls back', (tester) async {
      var tries = 0;
      await pump(tester, onRetry: () => tries++);

      await tester.tap(find.text('حاول تاني'));
      await tester.pump();

      expect(tries, 1);
    });

    // Some screens have nothing to retry — a section inside a page that reloads as a
    // whole. Offering a button that does nothing is worse than offering none.
    testWidgets('shows no button when there is nothing to retry', (tester) async {
      await pump(tester);

      expect(find.text('حاول تاني'), findsNothing);
    });

    // A screen-reader user has to be able to find it too, and an icon alone says
    // nothing to one.
    testWidgets('the retry control carries its own label', (tester) async {
      await pump(tester, onRetry: () {});

      expect(
        find.bySemanticsLabel(RegExp('حاول تاني')),
        findsAtLeastNWidgets(1),
      );
    });
  });

  group('inline', () {
    // A failed banner slot inside a working home screen must not take over the page.
    testWidgets('the compact form still says what went wrong', (tester) async {
      await pump(tester, compact: true, failure: const OfflineFailure());

      expect(find.text('مفيش اتصال بالإنترنت — الطلب مااتبعتش'), findsOneWidget);
    });

    testWidgets('and still lets you try again', (tester) async {
      var tries = 0;
      await pump(tester, compact: true, onRetry: () => tries++);

      await tester.tap(find.text('حاول تاني'));
      await tester.pump();

      expect(tries, 1);
    });
  });
}
