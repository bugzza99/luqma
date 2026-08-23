import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/app/merchant_app.dart';
import 'package:merchant_app/src/auth/sign_in_screen.dart';
import 'package:merchant_app/src/menu/menu_screen.dart';
import 'package:merchant_app/src/orders/inbox_screen.dart';
import 'package:merchant_app/src/orders/live_board_screen.dart';
import 'package:merchant_app/src/shop/busy_toggle.dart';
import 'package:merchant_app/src/shop/shop_screen.dart';

/// Getting into the app, and moving around it once inside.
void main() {
  const alwaysOpen = [
    OpeningWindow(weekday: DateTime.monday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.tuesday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.wednesday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.thursday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.friday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.saturday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.sunday, openMinute: 0, closeMinute: 1440),
  ];

  const shop = Merchant(
    id: 'm1',
    cityId: 'edku',
    type: MerchantType.restaurant,
    name: 'مطعم الشاطئ',
    zoneId: 'z1',
    phone: '01000000000',
    status: MerchantStatus.approved,
    openingHours: alwaysOpen,
    menuCategories: [MenuCategory(id: 'c1', name: 'مشويات')],
  );

  const owner = LuqmaIdentity(
    uid: 'owner1',
    email: 'owner@luqma.test',
    claims: {'role': 'owner', 'scope': 'merchant', 'merchantId': 'm1'},
  );

  late FakeAuthService auth;

  Future<void> pump(
    WidgetTester tester, {
    LuqmaIdentity? signedInAs = owner,
  }) async {
    auth = FakeAuthService(restoring: signedInAs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: const [shop])),
          merchantOrderRepositoryProvider
              .overrideWithValue(FakeMerchantOrderRepository()),
          menuRepositoryProvider.overrideWithValue(
            FakeMenuRepository(categories: shop.menuCategories),
          ),
          feedbackRepositoryProvider.overrideWithValue(
            FakeFeedbackRepository(seed: const [
              CustomerRating(
                orderId: 'o1',
                merchantId: 'm1',
                stars: 2,
                comment: 'الأكل وصل بارد',
              ),
              CustomerRating(orderId: 'o2', merchantId: 'm1', stars: 5),
            ]),
          ),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
        ],
        child: const MerchantApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('getting in', () {
    testWidgets('nobody signed in lands on the sign-in screen', (tester) async {
      await pump(tester, signedInAs: null);
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('an owner lands on the inbox', (tester) async {
      await pump(tester);
      expect(find.byType(InboxScreen), findsOneWidget);
    });

    // A customer's Google account, or a courier, is signed in — with a real account,
    // just not one this app is for. "Sign in" would be the wrong thing to say.
    testWidgets('an account that owns no merchant is turned away, not asked to sign in',
        (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(uid: 'u1', email: 'x@y.z'),
      );

      expect(find.byType(SignInScreen), findsNothing);
      expect(find.byKey(MerchantApp.noAccessKey), findsOneWidget);
    });

    testWidgets('signing out returns to the sign-in screen', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();
      // The feedback list sits above it, so on a test-sized screen it is below the fold.
      await tester.scrollUntilVisible(
        find.byKey(ShopScreen.signOutKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ShopScreen.signOutKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ShopScreen.confirmSignOutKey));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
    });
  });

  group('moving around', () {
    testWidgets('the tabs switch', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.liveTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(LiveBoardScreen), findsOneWidget);

      await tester.tap(find.byKey(MerchantApp.menuTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(MenuScreen), findsOneWidget);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(ShopScreen), findsOneWidget);
    });

    // The inbox is where a merchant has to be able to get back to in one tap, always.
    testWidgets('the inbox is the first tab', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.menuTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantApp.inboxTabKey));
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
    });
  });

  group('the shop tab', () {
    // Whether the kitchen is taking orders is the thing a merchant changes most often
    // after answering one, so it sits at the top of its own tab rather than in a menu.
    testWidgets('carries the busy control', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();

      expect(find.byType(BusyToggle), findsOneWidget);
    });

    // Private to this merchant: it is how somebody finds out the food arrives cold
    // before the rating that says so becomes public.
    testWidgets('shows what customers wrote', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();

      expect(find.text('الأكل وصل بارد'), findsOneWidget);
    });

    testWidgets('says which shop this account is for', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();

      expect(find.text('مطعم الشاطئ'), findsWidgets);
    });
  });
}
