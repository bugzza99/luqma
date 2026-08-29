import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The three states every screen in this product has, in one place.
///
/// Twenty-eight screens hand-wrote the same `switch`, and the reason that matters is not
/// the line count. The error arm has to come first and has to match on `hasError` rather
/// than on the `AsyncError` type, because a stream that fails before it has ever emitted
/// stays `AsyncLoading` with the error hanging off it — match the type and the error arm
/// never fires and the screen spins for ever. That rule is written in `CLAUDE.md` as a
/// trap, was got wrong once on the merchant's order inbox where a silent evening is
/// money, and was one comment away from being got wrong again in twenty-eight places.
///
/// Encoded once, no screen can get it wrong.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LuqmaTheme.light,
        locale: const Locale('ar'),
        localizationsDelegates: LuqmaStrings.localizationsDelegates,
        supportedLocales: LuqmaStrings.supportedLocales,
        home: Scaffold(
          body: Directionality(textDirection: TextDirection.rtl, child: child),
        ),
      ),
    );
    await tester.pump();
  }

  Widget view(
    AsyncValue<List<String>> value, {
    VoidCallback? onRetry,
    Widget? empty,
  }) =>
      LuqmaAsyncView<List<String>>(
        value: value,
        onRetry: onRetry,
        empty: empty,
        isEmpty: (rows) => rows.isEmpty,
        builder: (context, rows) => Text('rows: ${rows.length}'),
      );

  testWidgets('data is drawn by the builder', (tester) async {
    await pump(tester, view(const AsyncValue.data(['a', 'b'])));
    expect(find.text('rows: 2'), findsOneWidget);
  });

  testWidgets('loading spins', (tester) async {
    await pump(tester, view(const AsyncValue.loading()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a plain error is shown with its retry', (tester) async {
    var retried = false;
    await pump(tester, view(
      AsyncValue.error(const OfflineFailure(), StackTrace.empty),
      onRetry: () => retried = true,
    ));

    expect(find.byType(LuqmaErrorView), findsOneWidget);
    await tester.tap(find.byType(TextButton).first);
    expect(retried, isTrue);
  });

  // The trap this widget exists for.
  testWidgets('a stream that fails before emitting shows the error, not a spinner',
      (tester) async {
    // The state Riverpod leaves behind when a stream fails before its first event:
    // `isLoading` is still true and the error is attached, so `case AsyncError()` never
    // fires. Built with the public constructor and the same two flags rather than the
    // package-internal `copyWithPrevious`.
    const failed = AsyncValue<List<String>>.error(
      OfflineFailure(),
      StackTrace.empty,
    );

    await pump(tester, view(failed));

    expect(find.byType(LuqmaErrorView), findsOneWidget,
        reason: 'matching the AsyncError type here spins for ever instead');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an empty result gets the empty view when one was given',
      (tester) async {
    await pump(tester, view(
      const AsyncValue.data([]),
      empty: const LuqmaEmptyView(title: 'مفيش حاجة'),
    ));

    expect(find.text('مفيش حاجة'), findsOneWidget);
    expect(find.text('rows: 0'), findsNothing);
  });

  testWidgets('and the builder when none was', (tester) async {
    await pump(tester, view(const AsyncValue.data([])));

    // A screen that draws its own empty row inside the list must keep doing so.
    expect(find.text('rows: 0'), findsOneWidget);
  });

  testWidgets('data already loaded is kept while a refresh is in flight',
      (tester) async {
    // A refresh in flight over data already delivered: `hasValue` stays true.
    const refreshing = AsyncValue<List<String>>.data(['a']);

    await pump(tester, view(refreshing));

    // Blanking a working screen to a spinner on every refresh is a flicker the customer
    // reads as the app losing their place.
    expect(find.text('rows: 1'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
