import 'package:admin_app/src/auth/gate_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Signing an admin in.
///
/// Staff accounts get an email and a password from the owner — there is no self-service
/// sign-up for any of them — so this screen is the whole of the way in.
void main() {
  late FakeAuthService auth;

  Future<void> pump(WidgetTester tester, {Failure? failure}) async {
    auth = FakeAuthService(failure: failure);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authServiceProvider.overrideWithValue(auth)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: SignInScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillIn(
    WidgetTester tester, {
    String email = 'admin@luqma.test',
    String password = 'luqma1234',
  }) async {
    await tester.enterText(find.byKey(SignInScreen.emailKey), email);
    await tester.enterText(find.byKey(SignInScreen.passwordKey), password);
  }

  testWidgets('a correct password signs in', (tester) async {
    await pump(tester);

    await fillIn(tester);
    await tester.tap(find.byKey(SignInScreen.submitKey));
    await tester.pumpAndSettle();

    expect(auth.identity, isNotNull);
  });

  // Not "invalid credential", which tells somebody standing in a shop nothing they can
  // act on, and not the raw Firebase code.
  testWidgets('a wrong password says the details are wrong', (tester) async {
    await pump(tester, failure: const PermissionFailure());

    await fillIn(tester, password: 'nope');
    await tester.tap(find.byKey(SignInScreen.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('البيانات غلط'), findsOneWidget);
  });

  // Being told your password is wrong when the problem is the wifi sends somebody
  // resetting a password that was never broken.
  testWidgets('no connection says so, and does not blame the password',
      (tester) async {
    await pump(tester, failure: const OfflineFailure());

    await fillIn(tester);
    await tester.tap(find.byKey(SignInScreen.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('مفيش اتصال بالإنترنت'), findsOneWidget);
    expect(find.text('البيانات غلط'), findsNothing);
  });

  testWidgets('an empty form is refused before anything is sent', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(SignInScreen.submitKey));
    await tester.pumpAndSettle();

    expect(auth.identity, isNull);
  });

  testWidgets('a failed attempt can be tried again', (tester) async {
    await pump(tester, failure: const PermissionFailure());

    await fillIn(tester, password: 'nope');
    await tester.tap(find.byKey(SignInScreen.submitKey));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(SignInScreen.submitKey),
    );
    expect(button.onPressed, isNotNull);
  });
}
