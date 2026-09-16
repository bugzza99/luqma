import 'package:customer_app/src/account/account_screen.dart';
import 'package:customer_app/src/address/address_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// حسابي — who you are, where you live, what reaches you, and the way out.
void main() {
  late FakeAuthService auth;
  late FakeExternalLinks links;
  late FakeAddressRepository addressRepo;
  late FakeThemeModeStore themes;

  const edkuZones = [
    Zone(id: 'z1', cityId: 'edku', name: 'المعمورة'),
    Zone(id: 'z2', cityId: 'edku', name: 'الشط'),
  ];

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
    List<Address> addresses = const [],
    List<Zone> zones = const [],
    bool reducedMotion = false,
  }) async {
    // A test window is not a phone — `flutter test` defaults to 800x600, wider than tall.
    // The redesigned screen is a column that runs well past one screen, so it is sized
    // to the artboard's own frame here and revealed before every tap.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    auth = FakeAuthService(restoring: signedInAs, failure: failure);
    links = FakeExternalLinks(answer: phoneCanOpenLinks);
    themes = FakeThemeModeStore();
    addressRepo = FakeAddressRepository(
      seed: {
        if (signedInAs != null && addresses.isNotEmpty) signedInAs.uid: addresses,
      },
    );
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
          addressRepositoryProvider.overrideWithValue(addressRepo),
          profileRepositoryProvider
              .overrideWithValue(profiles ?? FakeProfileRepository()),
          geographyRepositoryProvider
              .overrideWithValue(FakeGeographyRepository(zones: zones)),
          externalLinksProvider.overrideWithValue(links),
          remoteConfigServiceProvider.overrideWithValue(config),
          appVersionProvider.overrideWithValue(appVersion),
          themeModeStoreProvider.overrideWithValue(themes),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reducedMotion),
              child: const Directionality(
                textDirection: TextDirection.rtl,
                child: AccountScreen(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Brings a control into the viewport before it is tapped — the screen is taller than
  /// the frame. The outermost scrollable is named because the sign-in card has fields of
  /// its own, each of which is a scrollable too.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Fills the sign-in card in whichever mode it is currently showing.
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

    // The avatar is drawn from the name rather than fetched — a network round-trip is
    // the one thing this screen would otherwise wait on.
    testWidgets('the profile card carries an avatar built from the name',
        (tester) async {
      await pump(tester);

      expect(
        find.descendant(
          of: find.byKey(AccountScreen.profileKey),
          matching: find.text('أ'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the addresses are on the screen, not behind a tile',
        (tester) async {
      await pump(
        tester,
        addresses: const [
          Address(
            id: 'a1',
            zoneId: 'z1',
            label: 'البيت',
            landmarkName: 'صيدلية النور',
            building: '12',
          ),
          Address(id: 'a2', zoneId: 'z2', label: 'الشغل'),
        ],
        zones: edkuZones,
      );
      await reveal(tester, find.byKey(AccountScreen.addressCardKey('a1')));

      // Both, right here — no navigation.
      expect(find.text('البيت'), findsOneWidget);
      expect(find.text('الشغل'), findsOneWidget);
      // And the courier line the second card was built from.
      expect(find.textContaining('صيدلية النور'), findsOneWidget);
    });

    // Production change that fails this: drawing every address card the same, or dropping
    // the pill — the default is the one an order actually goes to.
    testWidgets('the default address is outlined and pilled, the rest plain',
        (tester) async {
      await pump(
        tester,
        addresses: const [
          Address(id: 'a1', zoneId: 'z1', label: 'البيت'),
          Address(id: 'a2', zoneId: 'z2', label: 'الشغل'),
        ],
        zones: edkuZones,
      );
      await reveal(tester, find.byKey(AccountScreen.addressCardKey('a1')));

      expect(
        find.descendant(
          of: find.byKey(AccountScreen.addressCardKey('a1')),
          matching: find.text('الافتراضي'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(AccountScreen.addressCardKey('a2')),
          matching: find.text('الافتراضي'),
        ),
        findsNothing,
      );

      // White on burgundy — the pair `theme_test.dart` pins as the primary-button pair.
      final pill = tester.widget<Text>(
        find.descendant(
          of: find.byKey(AccountScreen.addressCardKey('a1')),
          matching: find.text('الافتراضي'),
        ),
      );
      expect(pill.style?.color, LuqmaColors.light.onBrand);

      Color borderColour(String id) {
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(AccountScreen.addressCardKey(id)),
                matching: find.byType(Container),
              )
              .first,
        );
        return ((container.decoration! as BoxDecoration).border! as Border)
            .top
            .color;
      }

      expect(borderColour('a1'), LuqmaColors.light.brand);
      expect(borderColour('a2'), LuqmaColors.light.hairline);
    });

    // Production change that fails this: making the plain card display-only.
    testWidgets('tapping a plain address card promotes it to the default',
        (tester) async {
      await pump(
        tester,
        addresses: const [
          Address(id: 'a1', zoneId: 'z1', label: 'البيت'),
          Address(id: 'a2', zoneId: 'z2', label: 'الشغل'),
        ],
        zones: edkuZones,
      );
      await reveal(tester, find.byKey(AccountScreen.addressCardKey('a2')));

      expect((await addressRepo.defaultAddressId('u1')).valueOrNull, 'a1');

      await tester.tap(find.byKey(AccountScreen.addressCardKey('a2')));
      await tester.pumpAndSettle();

      expect((await addressRepo.defaultAddressId('u1')).valueOrNull, 'a2');
      expect(
        find.descendant(
          of: find.byKey(AccountScreen.addressCardKey('a2')),
          matching: find.text('الافتراضي'),
        ),
        findsOneWidget,
      );
    });

    // Production change that fails this: `color: colors.hairline` on the dashed outline,
    // or a null handler on the button.
    testWidgets('أضف عنوان uses the strong outline and opens the editor',
        (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(AccountScreen.addAddressKey));

      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byKey(AccountScreen.addAddressKey),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((cp) => cp.painter)
          .whereType<DashedBorderPainter>()
          .single;
      expect(painter.color, LuqmaColors.light.border);
      expect(painter.color, isNot(LuqmaColors.light.hairline));

      await tester.tap(find.byKey(AccountScreen.addAddressKey));
      await tester.pumpAndSettle();
      expect(find.byType(AddressEditorScreen), findsOneWidget);
      // «عنوان التوصيل» since the redesign — the artboard's copy, and the same bar
      // whether the editor is reached from here or from checkout. Every address this app
      // stores is somewhere a courier drives to, so one title is right for both doors.
      expect(find.text('عنوان التوصيل'), findsOneWidget);
    });

    testWidgets('leads to the addresses inline', (tester) async {
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
      await reveal(tester, find.byKey(AccountScreen.signOutKey));

      await tester.tap(find.byKey(AccountScreen.signOutKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AccountScreen.confirmSignOutKey), findsOneWidget);
      expect(auth.identity, isNotNull);
    });

    testWidgets('confirming signs out and the screen changes', (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(AccountScreen.signOutKey));

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

    // The artboard has no delete control at all. It has to stay — Google Play requires
    // in-app deletion from any app that makes accounts — and it sits below sign-out,
    // quieter, because it is rarer and more final. Production change that fails this:
    // inheriting the artboard's absence, or moving it above sign-out.
    testWidgets('delete-account survives the artboard, and sits below sign-out',
        (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(AccountScreen.deleteAccountKey));

      expect(find.byKey(AccountScreen.deleteAccountKey), findsOneWidget);
      expect(find.byKey(AccountScreen.signOutKey), findsOneWidget);

      final signOut = tester.getRect(find.byKey(AccountScreen.signOutKey));
      final delete = tester.getRect(find.byKey(AccountScreen.deleteAccountKey));
      expect(delete.top, greaterThan(signOut.bottom));
    });

    // The blocks stagger in — the whole reason the redesign exists is the screen "did
    // not move". Production change that fails this: dropping the entrance wrappers.
    testWidgets('every block arrives through LuqmaEntrance', (tester) async {
      await pump(tester);
      // profile, addresses, notifications, support.
      expect(find.byType(LuqmaEntrance), findsNWidgets(4));
    });
  });

  group('the notifications card', () {
    // The artboard draws two switches; only `marketing_push` is a real preference. The
    // order-status row is a statement — a switch there would be a control that does
    // nothing every time the screen opens. Production change that fails this: rendering
    // the order-status row as a switch too.
    testWidgets('order status is a statement, not a second switch', (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(AccountScreen.orderStatusNoticeKey));

      // One switch on the whole screen — the offers one.
      expect(find.byType(Switch), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(AccountScreen.orderStatusNoticeKey),
          matching: find.byType(Switch),
        ),
        findsNothing,
      );
      // And nothing to press: no pressable wraps it.
      expect(
        find.ancestor(
          of: find.byKey(AccountScreen.orderStatusNoticeKey),
          matching: find.byType(LuqmaPressable),
        ),
        findsNothing,
      );

      // The label stays, and the card says in the artboard's own words why the row
      // cannot be turned off.
      expect(find.text('حالة الطلب'), findsOneWidget);
      expect(find.textContaining('إشعارات حالة الطلب مبتتقفلش'), findsOneWidget);
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
      expect(find.byKey(AccountScreen.orderStatusNoticeKey), findsNothing);
    });

    testWidgets('only the sign-in card and the support card arrive with an entrance',
        (tester) async {
      await pump(tester, signedInAs: null);
      expect(find.byType(LuqmaEntrance), findsNWidgets(2));
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
      await reveal(tester, find.byKey(AccountScreen.signOutKey));
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

    // The row used to be drawn unconditionally over an empty `onTap`, which is how a
    // support line can look staffed and answer nobody.
    testWidgets('and it actually opens the number the owner set', (tester) async {
      await pump(tester, supportWhatsapp: '01012345678');
      await reveal(tester, find.byKey(AccountScreen.contactKey));

      await tester.tap(find.byKey(AccountScreen.contactKey));
      await tester.pumpAndSettle();

      expect(links.opened.single, Uri.parse('https://wa.me/201012345678'));
    });

    testWidgets('a phone with no WhatsApp is told the number instead',
        (tester) async {
      // Silence after a tap is indistinguishable from a broken button, and the person
      // tapping it is already having a problem — which is why they are on this row.
      await pump(
        tester,
        supportWhatsapp: '01012345678',
        phoneCanOpenLinks: false,
      );
      await reveal(tester, find.byKey(AccountScreen.contactKey));

      await tester.tap(find.byKey(AccountScreen.contactKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('01012345678'), findsWidgets);
    });

    testWidgets('no number set is no row', (tester) async {
      // An icon that goes nowhere is worse than no icon — the rule حول لقمة already
      // applies to its own links.
      await pump(tester);
      expect(find.byKey(AccountScreen.contactKey), findsNothing);
    });
  });

  // The build number belongs to the app, not to the owner. It used to sit on حول لقمة
  // directly beneath their photo and description. Here it is a quiet footer on the
  // customer's own settings, the place every app puts it — still one tap from a support
  // call.
  group('the build number', () {
    testWidgets('is a footer on حسابي', (tester) async {
      await pump(tester);

      // A footer is at the bottom, and «عن المطور» added one more row above it — so on a
      // signed-in account it sits below the fold and a lazy list has not built it yet.
      // Scrolled to, not asserted on sight: the body scrolls, which is what makes this a
      // test about the footer rather than about the height of the test window.
      await tester.scrollUntilVisible(
        find.byKey(AccountScreen.versionKey),
        300,
        scrollable: find.byType(Scrollable).first,
      );
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
  group('شكل التطبيق', () {
    // Both themes have existed since Phase 0 and `themeMode` was never set, so the app
    // followed the phone with no way to say otherwise from inside it.
    // The label was clipped to «حسب» when the three chips were forced into equal thirds
    // of a phone's width — the option that needs explaining most, cut to a preposition.
    testWidgets('says what following the phone means, in full', (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(AccountScreen.appearanceKey));

      final chip = tester.widget<LuqmaChip>(
        find.byKey(AccountScreen.appearanceOptionKey(ThemeMode.system)),
      );
      expect(chip.label, 'حسب الموبايل');
      // Rendered, not merely passed: the clipping happened inside the chip.
      final painted = tester.renderObject<RenderBox>(
        find.byKey(AccountScreen.appearanceOptionKey(ThemeMode.system)),
      );
      final text = tester.renderObject<RenderBox>(
        find.descendant(
          of: find.byKey(AccountScreen.appearanceOptionKey(ThemeMode.system)),
          matching: find.byType(Text),
        ),
      );
      expect(text.size.width, lessThanOrEqualTo(painted.size.width),
          reason: 'the words fit inside the chip drawn around them');
    });

    testWidgets('starts on the phone’s own setting', (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(AccountScreen.appearanceKey));

      final chip = tester.widget<LuqmaChip>(
        find.byKey(AccountScreen.appearanceOptionKey(ThemeMode.system)),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('choosing dark changes the app and is remembered', (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(AccountScreen.appearanceKey));

      await tester.tap(find.byKey(AccountScreen.appearanceOptionKey(ThemeMode.dark)));
      await tester.pumpAndSettle();

      // On screen…
      final chip = tester.widget<LuqmaChip>(
        find.byKey(AccountScreen.appearanceOptionKey(ThemeMode.dark)),
      );
      expect(chip.selected, isTrue);
      // …and written, which is the half that survives the next launch.
      expect(themes.mode, ThemeMode.dark);
    });

    // A switch could not express this: somebody who pinned the app to light and then
    // wants it to follow their handset again needs a way back.
    testWidgets('and going back to the phone’s setting is reachable',
        (tester) async {
      await pump(tester);
      await reveal(tester, find.byKey(AccountScreen.appearanceKey));

      await tester.tap(find.byKey(AccountScreen.appearanceOptionKey(ThemeMode.light)));
      await tester.pumpAndSettle();
      expect(themes.mode, ThemeMode.light);

      await tester.tap(find.byKey(AccountScreen.appearanceOptionKey(ThemeMode.system)));
      await tester.pumpAndSettle();
      expect(themes.mode, ThemeMode.system);
    });
  });
}
