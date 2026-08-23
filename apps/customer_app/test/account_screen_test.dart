import 'package:customer_app/src/account/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// حسابي — who you are, where you live, and the way out.
void main() {
  late FakeAuthService auth;

  Future<void> pump(
    WidgetTester tester, {
    LuqmaIdentity? signedInAs = const LuqmaIdentity(
      uid: 'u1',
      name: 'أحمد محمود',
      email: 'ahmed@example.com',
    ),
  }) async {
    auth = FakeAuthService(restoring: signedInAs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          addressRepositoryProvider.overrideWithValue(FakeAddressRepository()),
          geographyRepositoryProvider
              .overrideWithValue(FakeGeographyRepository()),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: AccountScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('signed in', () {
    testWidgets('says who you are', (tester) async {
      await pump(tester);

      expect(find.text('أحمد محمود'), findsOneWidget);
      expect(find.text('ahmed@example.com'), findsOneWidget);
    });

    testWidgets('leads to the addresses', (tester) async {
      await pump(tester);
      expect(find.byKey(AccountScreen.addressesKey), findsOneWidget);
    });

    // Somebody who cannot find their way out of an account trusts it less, not more.
    testWidgets('offers a way out', (tester) async {
      await pump(tester);
      expect(find.byKey(AccountScreen.signOutKey), findsOneWidget);
    });

    testWidgets('signing out asks first', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(AccountScreen.signOutKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AccountScreen.confirmSignOutKey), findsOneWidget);
      expect(auth.identity, isNotNull);
    });

    testWidgets('confirming signs out and the screen changes', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(AccountScreen.signOutKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountScreen.confirmSignOutKey));
      await tester.pumpAndSettle();

      expect(auth.identity, isNull);
      expect(find.byKey(AccountScreen.signInKey), findsOneWidget);
    });
  });

  group('signed out', () {
    testWidgets('offers the way in, and nothing that needs an account',
        (tester) async {
      await pump(tester, signedInAs: null);

      expect(find.byKey(AccountScreen.signInKey), findsOneWidget);
      expect(find.byKey(AccountScreen.addressesKey), findsNothing);
      expect(find.byKey(AccountScreen.signOutKey), findsNothing);
    });

    testWidgets('signing in shows the account', (tester) async {
      await pump(tester, signedInAs: null);

      await tester.tap(find.byKey(AccountScreen.signInKey));
      await tester.pumpAndSettle();

      expect(find.text('عميل تجريبي'), findsOneWidget);
      expect(find.byKey(AccountScreen.signOutKey), findsOneWidget);
    });
  });

  group('what the app can always tell you', () {
    // A customer with a problem needs a way to reach a person, signed in or not.
    testWidgets('the way to reach us is there either way', (tester) async {
      await pump(tester, signedInAs: null);
      expect(find.byKey(AccountScreen.contactKey), findsOneWidget);

      await pump(tester);
      expect(find.byKey(AccountScreen.contactKey), findsOneWidget);
    });
  });
}
