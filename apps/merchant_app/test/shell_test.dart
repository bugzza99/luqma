import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/app/merchant_app.dart';
import 'package:merchant_app/src/auth/sign_in_screen.dart';
import 'package:merchant_app/src/courier/courier_screen.dart';
import 'package:merchant_app/src/meals/meals_screen.dart';
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
    Merchant shopIs = shop,
  }) async {
    auth = FakeAuthService(restoring: signedInAs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: [shopIs])),
          dailyMealRepositoryProvider
              .overrideWithValue(FakeDailyMealRepository()),
          billingRepositoryProvider.overrideWithValue(
            FakeBillingRepository(
              seedPlans: const [
                Plan(id: 'basic', name: 'أساسية', priceMonthly: 25000),
              ],
            ),
          ),
          merchantOrderRepositoryProvider
              .overrideWithValue(FakeMerchantOrderRepository()),
          courierOrderRepositoryProvider
              .overrideWithValue(FakeCourierOrderRepository()),
          geographyRepositoryProvider.overrideWithValue(FakeGeographyRepository()),
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

    // One app, two modes. A courier has no menu, no busy toggle and no inbox — there is
    // nothing on those screens they are allowed to touch.
    testWidgets('a courier lands on the delivery screen, not the inbox', (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(
          uid: 'c1',
          claims: {'role': 'courier', 'scope': 'merchant', 'merchantId': 'm1'},
        ),
      );

      expect(find.byType(CourierScreen), findsOneWidget);
      expect(find.byType(InboxScreen), findsNothing);
      expect(find.byKey(MerchantApp.menuTabKey), findsNothing);
    });

    testWidgets('a platform courier gets in too, with no merchant at all',
        (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(
          uid: 'c9',
          claims: {'role': 'courier', 'scope': 'platform'},
        ),
      );

      expect(find.byType(CourierScreen), findsOneWidget);
      expect(find.byKey(MerchantApp.noAccessKey), findsNothing);
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

  // A cook has no standing menu — what they sell is today's meal and a count of
  // portions — so the third tab is the one that matches the business.
  // Read-only on purpose: money is settled in cash with the owner, so a merchant
  // changing their own terms from their phone is not a feature, it is a hole.
  group('what the merchant pays', () {
    testWidgets('is shown on the shop tab', (tester) async {
      await pump(tester, shopIs: shop.copyWith(planId: 'basic'));

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ShopScreen.billingKey), findsOneWidget);
      expect(find.text('أساسية'), findsWidgets);
    });

    testWidgets('a prepaid merchant sees the balance', (tester) async {
      await pump(
        tester,
        shopIs: shop.copyWith(
          revenueModel: RevenueModel.prepaid,
          revenueValue: 500,
          walletBalance: 4000,
        ),
      );

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ShopScreen.walletKey), findsOneWidget);
      expect(find.textContaining('40 ج'), findsWidgets);
    });

    // The one line on that card that changes what happens next.
    testWidgets('an empty wallet says orders have stopped', (tester) async {
      await pump(
        tester,
        shopIs: shop.copyWith(
          revenueModel: RevenueModel.prepaid,
          revenueValue: 500,
          walletBalance: 100,
        ),
      );

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('مش هتوصلك طلبات'), findsOneWidget);
    });

    testWidgets('a subscriber sees no wallet at all', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();

      expect(find.byKey(ShopScreen.walletKey), findsNothing);
    });
  });

  group('a home kitchen', () {
    testWidgets('gets the meals tab instead of the menu', (tester) async {
      await pump(
        tester,
        shopIs: shop.copyWith(type: MerchantType.homeKitchen),
      );

      expect(find.byKey(MerchantApp.mealsTabKey), findsOneWidget);
      expect(find.byKey(MerchantApp.menuTabKey), findsNothing);

      await tester.tap(find.byKey(MerchantApp.mealsTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(MealsScreen), findsOneWidget);
    });

    testWidgets('a restaurant keeps the menu', (tester) async {
      await pump(tester);

      expect(find.byKey(MerchantApp.menuTabKey), findsOneWidget);
      expect(find.byKey(MerchantApp.mealsTabKey), findsNothing);
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
