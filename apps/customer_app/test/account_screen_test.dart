import 'package:customer_app/src/account/account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// حسابي — who you are, where you live, and the way out.
void main() {
  late FakeAuthService auth;
  late FakeExternalLinks links;

  Future<void> pump(
    WidgetTester tester, {
    LuqmaIdentity? signedInAs = const LuqmaIdentity(
      uid: 'u1',
      name: 'أحمد محمود',
      phone: '01012345678',
    ),
    Failure? failure,
    String? supportWhatsapp,
    bool phoneCanOpenLinks = true,
    // What `main()` reads off the package. Set here so the footer is exercised the way
    // it ships rather than against the empty default.
    String appVersion = '1.0.0 (1)',
    FakeProfileRepository? profiles,
  }) async {
    auth = FakeAuthService(restoring: signedInAs, failure: failure);
    links = FakeExternalLinks(answer: phoneCanOpenLinks);
    // `AppConfig` starts on the compiled-in defaults; nothing reads the fetcher until
    // somebody refreshes, so a value handed to the fake alone would never be seen.
    final config = RemoteConfigService(FakeConfigFetcher({
      'support_whatsapp': ?supportWhatsapp,
    }));
    await config.refresh();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          addressRepositoryProvider.overrideWithValue(FakeAddressRepository()),
          profileRepositoryProvider
              .overrideWithValue(profiles ?? FakeProfileRepository()),
          geographyRepositoryProvider
              .overrideWithValue(FakeGeographyRepository()),
          externalLinksProvider.overrideWithValue(links),
          remoteConfigServiceProvider.overrideWithValue(config),
          appVersionProvider.overrideWithValue(appVersion),
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

  /// Fills the card in whichever mode it is currently showing.
  Future<void> fillIn(
    WidgetTester tester, {
    String phone = '01012345678',
    String password = 'a-real-password',
    String? name,
  }) async {
    if (name != null) {
      await tester.enterText(find.byKey(AccountScreen.nameKey), name);
    }
    await tester.enterText(find.byKey(AccountScreen.phoneKey), phone);
    await tester.enterText(find.byKey(AccountScreen.passwordKey), password);
  }

  group('signed in', () {
    // The number, not an address: a customer's account has no email to show, and the
    // number is the thing they recognise as theirs.
    testWidgets('says who you are, by name and number', (tester) async {
      await pump(tester);

      expect(find.text('أحمد محمود'), findsOneWidget);
      expect(find.text('01012345678'), findsOneWidget);
    });

    testWidgets('leads to the addresses', (tester) async {
      await pump(tester);
      expect(find.byKey(AccountScreen.addressesKey), findsOneWidget);
    });

    // Somebody who cannot find their way out of an account trusts it less, not more.
    testWidgets('offers a way out', (tester) async {
      await pump(tester);
      expect(find.byKey(AccountScreen.signOutKey), findsOneWidget);
      expect(find.byKey(AccountScreen.deleteAccountKey), findsOneWidget);
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

    testWidgets('account deletion explains the retained financial record',
        (tester) async {
      final profiles = FakeProfileRepository();
      await pump(tester, profiles: profiles);
      await tester.scrollUntilVisible(
        find.byKey(AccountScreen.deleteAccountKey),
        200,
      );

      await tester.tap(find.byKey(AccountScreen.deleteAccountKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('سجل الطلبات هيفضل محفوظ'), findsOneWidget);
      expect(find.textContaining('اسمك ورقمك هيتشالوا منه'), findsOneWidget);
      expect(find.textContaining('حساب جديد من غير أي تاريخ قديم'), findsOneWidget);
      expect(find.byKey(AccountScreen.confirmDeleteAccountKey), findsOneWidget);
      expect(auth.identity, isNotNull);
      expect(profiles.accountDeleted, false);
    });

    testWidgets('confirming permanently deletes and returns to signed out',
        (tester) async {
      final profiles = FakeProfileRepository();
      await pump(tester, profiles: profiles);
      await tester.scrollUntilVisible(
        find.byKey(AccountScreen.deleteAccountKey),
        200,
      );

      await tester.tap(find.byKey(AccountScreen.deleteAccountKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountScreen.confirmDeleteAccountKey));
      await tester.pumpAndSettle();

      expect(profiles.accountDeleted, true);
      expect(auth.identity, isNull);
      expect(find.byKey(AccountScreen.signInKey), findsOneWidget);
    });

    testWidgets('a refused deletion uses the shared error view and keeps the session',
        (tester) async {
      final profiles = FakeProfileRepository(isStaffAccount: true);
      await pump(tester, profiles: profiles);
      await tester.scrollUntilVisible(
        find.byKey(AccountScreen.deleteAccountKey),
        200,
      );

      await tester.tap(find.byKey(AccountScreen.deleteAccountKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountScreen.confirmDeleteAccountKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AccountScreen.deleteAccountErrorKey), findsOneWidget);
      expect(auth.identity, isNotNull);
      expect(profiles.accountDeleted, false);
    });
  });

  group('signed out', () {
    testWidgets('offers the way in, and nothing that needs an account',
        (tester) async {
      await pump(tester, signedInAs: null);

      expect(find.byKey(AccountScreen.signInKey), findsOneWidget);
      expect(find.byKey(AccountScreen.addressesKey), findsNothing);
      expect(find.byKey(AccountScreen.signOutKey), findsNothing);
      expect(find.byKey(AccountScreen.deleteAccountKey), findsNothing);
    });

    // Signing in is the default face of the card: most people opening it already have
    // an account, and the one who does not is one tap away.
    testWidgets('asks for a number and a password, not a name', (tester) async {
      await pump(tester, signedInAs: null);

      expect(find.byKey(AccountScreen.phoneKey), findsOneWidget);
      expect(find.byKey(AccountScreen.passwordKey), findsOneWidget);
      expect(find.byKey(AccountScreen.nameKey), findsNothing);
    });

    testWidgets('signing in shows the account', (tester) async {
      await pump(tester, signedInAs: null);

      await fillIn(tester);
      await tester.tap(find.byKey(AccountScreen.signInKey));
      await tester.pumpAndSettle();

      expect(auth.identity, isNotNull);
      expect(find.byKey(AccountScreen.signOutKey), findsOneWidget);
    });

    // Never "invalid credentials", and never which of the two was wrong: telling
    // somebody the number exists but the password did not is a way to enumerate numbers.
    testWidgets('a refused sign-in says so without saying which half',
        (tester) async {
      await pump(tester, signedInAs: null, failure: const PermissionFailure());

      await fillIn(tester);
      await tester.tap(find.byKey(AccountScreen.signInKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AccountScreen.errorKey), findsOneWidget);
      expect(find.text('رقم الموبايل أو كلمة السر غلط'), findsOneWidget);
    });
  });

  group('making an account', () {
    testWidgets('the card turns into a sign-up and asks for a name',
        (tester) async {
      await pump(tester, signedInAs: null);

      await tester.tap(find.byKey(AccountScreen.toggleModeKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AccountScreen.nameKey), findsOneWidget);
    });

    testWidgets('signing up signs you in, carrying the number you typed',
        (tester) async {
      await pump(tester, signedInAs: null);
      await tester.tap(find.byKey(AccountScreen.toggleModeKey));
      await tester.pumpAndSettle();

      await fillIn(tester, name: 'سارة', phone: '01099887766');
      await tester.tap(find.byKey(AccountScreen.signInKey));
      await tester.pumpAndSettle();

      expect(auth.identity?.name, 'سارة');
      expect(auth.identity?.phone, '01099887766',
          reason: 'the courier calls this, so it has to be what they typed');
    });

    // The number is the identity. A second account on it is somebody who already has
    // history under that number — and should be signing in, not signing up.
    testWidgets('a number that already has an account says to sign in instead',
        (tester) async {
      await pump(tester, signedInAs: null);
      await tester.tap(find.byKey(AccountScreen.toggleModeKey));
      await tester.pumpAndSettle();

      await fillIn(tester, name: 'سارة');
      await tester.tap(find.byKey(AccountScreen.signInKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountScreen.signOutKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountScreen.confirmSignOutKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(AccountScreen.toggleModeKey));
      await tester.pumpAndSettle();
      await fillIn(tester, name: 'شخص تاني');
      await tester.tap(find.byKey(AccountScreen.signInKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AccountScreen.errorKey), findsOneWidget);
    });
  });

  group('what the form refuses before it asks the server', () {
    testWidgets('a number that is not an Egyptian mobile', (tester) async {
      await pump(tester, signedInAs: null);

      await fillIn(tester, phone: '0201234');
      await tester.tap(find.byKey(AccountScreen.signInKey));
      await tester.pumpAndSettle();

      expect(auth.identity, isNull, reason: 'nothing was sent');
      expect(find.textContaining('رقم موبايل مصري صحيح'), findsOneWidget);
    });

    // Only on the way in: an existing account's password was accepted once already, and
    // a minimum introduced afterwards must not lock it out.
    testWidgets('a password too short to be one, when signing up',
        (tester) async {
      await pump(tester, signedInAs: null);
      await tester.tap(find.byKey(AccountScreen.toggleModeKey));
      await tester.pumpAndSettle();

      await fillIn(tester, name: 'سارة', password: '123');
      await tester.tap(find.byKey(AccountScreen.signInKey));
      await tester.pumpAndSettle();

      expect(auth.identity, isNull);
      expect(find.textContaining('6 حروف على الأقل'), findsOneWidget);
    });

    testWidgets('a short password is not refused when signing in',
        (tester) async {
      await pump(tester, signedInAs: null);

      await fillIn(tester, password: '123');
      await tester.tap(find.byKey(AccountScreen.signInKey));
      await tester.pumpAndSettle();

      expect(auth.identity, isNotNull);
    });
  });

  group('what the app can always tell you', () {
    // A customer with a problem needs a way to reach a person, signed in or not.
    testWidgets('the way to reach us is there either way', (tester) async {
      await pump(tester, signedInAs: null, supportWhatsapp: '01012345678');
      expect(find.byKey(AccountScreen.contactKey), findsOneWidget);

      await pump(tester, supportWhatsapp: '01012345678');
      expect(find.byKey(AccountScreen.contactKey), findsOneWidget);
    });

    // The tile used to be drawn unconditionally over an empty `onTap`, which is how a
    // support line can look staffed and answer nobody. `support_whatsapp` had been
    // carried from AdminApp to the phone since Phase 1 and read by no screen at all.
    testWidgets('and it actually opens the number the owner set', (tester) async {
      await pump(tester, supportWhatsapp: '01012345678');

      await tester.tap(find.byKey(AccountScreen.contactKey));
      await tester.pumpAndSettle();

      expect(links.opened.single, Uri.parse('https://wa.me/201012345678'));
    });

    testWidgets('a phone with no WhatsApp is told the number instead',
        (tester) async {
      // Silence after a tap is indistinguishable from a broken button, and the person
      // tapping it is already having a problem — which is why they are on this tile.
      await pump(
        tester,
        supportWhatsapp: '01012345678',
        phoneCanOpenLinks: false,
      );

      await tester.tap(find.byKey(AccountScreen.contactKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('01012345678'), findsWidgets);
    });

    testWidgets('no number set is no tile', (tester) async {
      // An icon that goes nowhere is worse than no icon — the rule حول لقمة already
      // applies to its own links.
      await pump(tester);
      expect(find.byKey(AccountScreen.contactKey), findsNothing);
    });
  });

  // The build number belongs to the app, not to the owner. It used to sit on حول لقمة
  // directly beneath their photo and description, which made technical detail read as
  // part of who they are. Here it is a quiet footer on the customer's own settings, the
  // place every app puts it — still one tap from a support call.
  group('the build number', () {
    testWidgets('is a footer on حسابي', (tester) async {
      await pump(tester);

      expect(find.byKey(AccountScreen.versionKey), findsOneWidget);
      expect(find.textContaining('نسخة'), findsOneWidget);
    });

    testWidgets('and is shown signed out too, because support calls come from anybody',
        (tester) async {
      await pump(tester, signedInAs: null);

      expect(find.byKey(AccountScreen.versionKey), findsOneWidget);
    });

    // A build that cannot say what it is says nothing, rather than a wrong number —
    // which is what a hardcoded second copy eventually becomes.
    testWidgets('a build with no version draws no footer', (tester) async {
      await pump(tester, appVersion: '');

      expect(find.byKey(AccountScreen.versionKey), findsNothing);
    });
  });

  group('the offers switch', () {
    // The channel is sold to merchants and reaches somebody who is not looking at the
    // app, which is exactly why there has to be a way out of it. Until this existed
    // there was none.
    testWidgets('is on for an account that never touched it', (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.byKey(AccountScreen.marketingKey), 200);

      expect(
        tester.widget<SwitchListTile>(find.byKey(AccountScreen.marketingKey)).value,
        true,
      );
    });

    testWidgets('turning it off reaches the repository', (tester) async {
      final profiles = FakeProfileRepository();
      await pump(tester, profiles: profiles);
      await tester.scrollUntilVisible(find.byKey(AccountScreen.marketingKey), 200);

      await tester.tap(find.byKey(AccountScreen.marketingKey));
      await tester.pumpAndSettle();

      expect(profiles.marketing['u1'], false);
    });

    // A switch that stays where somebody left it while the write failed is a switch that
    // lies about what it did.
    testWidgets('goes back where it was when the write fails', (tester) async {
      await pump(
        tester,
        profiles: FakeProfileRepository(writeFailure: const OfflineFailure()),
      );
      await tester.scrollUntilVisible(find.byKey(AccountScreen.marketingKey), 200);

      await tester.tap(find.byKey(AccountScreen.marketingKey));
      await tester.pumpAndSettle();

      expect(
        tester.widget<SwitchListTile>(find.byKey(AccountScreen.marketingKey)).value,
        true,
      );
    });

    // Drawing it in a state nobody chose would be worse than not drawing it: the offers
    // keep arriving either way, which is the state the account was already in.
    testWidgets('is not drawn at all when it cannot be read', (tester) async {
      await pump(
        tester,
        profiles: FakeProfileRepository(failure: const OfflineFailure()),
      );

      expect(find.byKey(AccountScreen.marketingKey), findsNothing);
    });

    testWidgets('is not offered to somebody signed out', (tester) async {
      await pump(tester, signedInAs: null);

      expect(find.byKey(AccountScreen.marketingKey), findsNothing);
    });
  });
}
