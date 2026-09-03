import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Starting up, and failing to.
///
/// Every `main` in this workspace awaits three or four things before `runApp` — Sentry,
/// Supabase, the package version — and none of it used to be inside a `try`. An async
/// `main` whose body throws never reaches `runApp` at all: Android shows the launch theme
/// for an instant and the process ends, which to whoever is holding the phone is
/// identical to tapping the icon and nothing happening. No screen, no message, and
/// nowhere to report it from — and `LuqmaTelemetry.init()` runs first, so a failure there
/// is invisible to Sentry too.
void main() {
  testWidgets('a start-up that works runs the app', (tester) async {
    await luqmaBootstrap(() async => const MaterialApp(home: Text('open')));
    await tester.pump();

    expect(find.text('open'), findsOneWidget);
    expect(find.byType(LuqmaStartupFailure), findsNothing);
  });

  testWidgets('a start-up that throws draws a screen instead of nothing',
      (tester) async {
    await luqmaBootstrap(() async => throw StateError('supabase would not start'));
    await tester.pumpAndSettle();

    expect(find.byKey(LuqmaStartupFailure.messageKey), findsOneWidget);
  });

  // The one person who can act on this is whoever the customer telephones, and
  // "التطبيق مش بيفتح" on its own is close to unactionable.
  testWidgets('and says what went wrong, for whoever they call', (tester) async {
    await luqmaBootstrap(() async => throw StateError('supabase would not start'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('supabase would not start'),
      findsOneWidget,
    );
  });

  // Told what to do rather than apologised to. Closing and reopening genuinely starts
  // over, which is why there is no retry button offering to do it in place.
  testWidgets('and what to do about it', (tester) async {
    await luqmaBootstrap(() async => throw StateError('nope'));
    await tester.pumpAndSettle();

    expect(find.textContaining('اقفل التطبيق'), findsOneWidget);
  });
}
