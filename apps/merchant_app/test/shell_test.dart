import 'dart:async';
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
import 'package:merchant_app/src/shop/subscription_screen.dart';

/// An account that is approved between one look at the token and the next.
///
/// The claims live on the access token, stamped at sign-in, so this is what the server
/// doing its job looks like from the phone: the same person, carrying a shop the moment the
/// token is asked for again. `FakeAuthService` cannot express that — its identity is fixed
/// at construction — and this is the one behaviour the refresh button exists for.
class _ApprovedOnRefresh implements AuthService {
  _ApprovedOnRefresh(this._before, this._after);

  final LuqmaIdentity _before;
  final LuqmaIdentity _after;
  final _controller = StreamController<LuqmaIdentity?>.broadcast();

  LuqmaIdentity? _identity;

  @override
  AuthState get state => _identity == null ? AuthState.unknown : AuthState.signedIn;

  @override
  LuqmaIdentity? get identity => _identity;

  @override
  Stream<LuqmaIdentity?> get changes => Stream.multi((listener) {
        listener.add(_identity);
        final sub = _controller.stream.listen(listener.add, onDone: listener.close);
        listener.onCancel = sub.cancel;
      });

  @override
  Future<void> restore() async {
    _identity = _before;
    _controller.add(_identity);
  }

  @override
  Future<Result<void>> refreshSession() async {
    _identity = _after;
    _controller.add(_identity);
    return const Result.ok(null);
  }

  @override
  Future<Result<LuqmaIdentity>> signInWithPhone({
    required String phone,
    required String password,
  }) async => Result.ok(_identity!);

  @override
  Future<Result<LuqmaIdentity>> signInWithPassword({
    required String email,
    required String password,
  }) async => Result.ok(_identity!);

  @override
  Future<Result<LuqmaIdentity>> signUpWithPhone({
    required String phone,
    required String password,
    required String name,
  }) async => Result.ok(_identity!);

  @override
  Future<void> signOut() async {
    _identity = null;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}

/// Getting into the app, and moving around it once inside.
void main() {
  setUp(() => LuqmaPush.tapped.value = null);
  tearDown(() => LuqmaPush.tapped.value = null);

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

  late AuthService auth;

  Future<void> pump(
    WidgetTester tester, {
    LuqmaIdentity? signedInAs = owner,
    Merchant shopIs = shop,
    // A fake of the test's own, for the two cases that are about what the *service* does
    // rather than about who is signed in.
    AuthService? signingIn,
  }) async {
    auth = signingIn ?? FakeAuthService(restoring: signedInAs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          pushTokenRepositoryProvider
              .overrideWithValue(FakePushTokenRepository()),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: [shopIs])),
          dailyMealRepositoryProvider
              .overrideWithValue(FakeDailyMealRepository()),
          subscriptionRequestRepositoryProvider
              .overrideWithValue(FakeSubscriptionRequestRepository()),
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
        child: const MerchantApp(currentVersion: '1.0.0'),
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

    // An approved partner is holding a token stamped before they were approved, and a
    // claim only reaches the phone when the token rotates. Without this button that is up
    // to an hour of reading «الحساب لسه مش مفعّل» straight after being told it worked.
    testWidgets('and can ask for the claims again once the call has happened',
        (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(uid: 'u1', phone: '01000000000'),
      );

      expect(find.byKey(MerchantApp.refreshAccessKey), findsOneWidget);

      await tester.tap(find.byKey(MerchantApp.refreshAccessKey));
      await tester.pumpAndSettle();

      // Nothing changed on the server, so it says so rather than leaving somebody
      // pressing a button that appears to do nothing.
      expect(find.textContaining('لسه مفيش تفعيل'), findsOneWidget);
    });

    // The whole point of the button: the approval landed while this phone was holding a
    // token stamped before it, and asking again is what turns the screen into a shop.
    testWidgets('and lands on the inbox once the refreshed token carries the claims',
        (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(uid: 'u1', phone: '01000000000'),
        signingIn: _ApprovedOnRefresh(
          const LuqmaIdentity(uid: 'u1', phone: '01000000000'),
          owner,
        ),
      );

      expect(find.byKey(MerchantApp.noAccessKey), findsOneWidget);

      await tester.tap(find.byKey(MerchantApp.refreshAccessKey));
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
      expect(find.byKey(MerchantApp.noAccessKey), findsNothing);
    });

    testWidgets('and says it is the network when the refresh cannot reach anybody',
        (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(uid: 'u1', phone: '01000000000'),
        signingIn: FakeAuthService(
          restoring: const LuqmaIdentity(uid: 'u1', phone: '01000000000'),
          failure: const OfflineFailure(),
        ),
      );

      await tester.tap(find.byKey(MerchantApp.refreshAccessKey));
      await tester.pumpAndSettle();

      // Not «لسه مفيش تفعيل»: that would send somebody back to the telephone over a
      // dropped connection.
      expect(find.textContaining('مفيش اتصال'), findsOneWidget);
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

    // Switching tabs shows the next one in place rather than pushing a route, which is
    // what keeps the inbox's live subscription alive — and what left the Navigator
    // holding a single entry. System back then found nothing to pop and closed the app,
    // taking the order alarm with it.
    testWidgets('back from another tab returns to the inbox rather than exiting',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(ShopScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('and back from the inbox is left to the system', (tester) async {
      await pump(tester);

      final popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(popped, isFalse);
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

    // The card used to be a plan name over a lone analytics link, which told the merchant
    // nothing about what they pay. One line of terms, true to each model.
    testWidgets('a subscriber is told there is no per-order charge', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();

      expect(find.text('مبلغ ثابت كل شهر، ومفيش عمولة على الطلبات.'), findsOneWidget);
    });

    testWidgets('a commission merchant sees the rate and that delivery is not charged',
        (tester) async {
      await pump(
        tester,
        shopIs: shop.copyWith(revenueModel: RevenueModel.commission, revenueValue: 750),
      );

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();

      expect(
        find.text('7.5% على الأكل بس. التوصيل مش بناخد منه حاجة.'),
        findsOneWidget,
      );
    });

    testWidgets('a prepaid merchant sees what each order takes', (tester) async {
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

      expect(find.textContaining('مع كل طلب يتوصّل، ومش أكتر من تمن الأكل'), findsOneWidget);
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

  group('tapped notifications', () {
    testWidgets('newOrder tap switches to the inbox tab', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(ShopScreen), findsOneWidget);

      LuqmaPush.tapped.value = const LuqmaTap(
        kind: 'newOrder',
        data: {'orderId': 'o-99'},
      );
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('an orderId tap without newOrder kind also switches to the inbox tab',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(ShopScreen), findsOneWidget);

      LuqmaPush.tapped.value = const LuqmaTap(
        data: {'orderId': 'o-legacy'},
      );
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
    });

    testWidgets('subscription_activated opens the subscription screen',
        (tester) async {
      await pump(tester);

      LuqmaPush.tapped.value = const LuqmaTap(
        kind: 'subscription_activated',
      );
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionScreen), findsOneWidget);
    });

    testWidgets('unrelated notification does not switch tab or open screen',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantApp.shopTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(ShopScreen), findsOneWidget);

      LuqmaPush.tapped.value = const LuqmaTap(
        kind: 'promotion',
        data: {'foo': 'bar'},
      );
      await tester.pumpAndSettle();

      expect(find.byType(ShopScreen), findsOneWidget);
      expect(find.byType(SubscriptionScreen), findsNothing);
    });

    testWidgets(
        'a staffApproved tap on the no-access screen calls refreshSession',
        (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(uid: 'u1', phone: '01000000000'),
        signingIn: _ApprovedOnRefresh(
          const LuqmaIdentity(uid: 'u1', phone: '01000000000'),
          owner,
        ),
      );

      expect(find.byKey(MerchantApp.noAccessKey), findsOneWidget);

      LuqmaPush.tapped.value = const LuqmaTap(kind: 'staffApproved');
      await tester.pumpAndSettle();

      expect(find.byType(InboxScreen), findsOneWidget);
      expect(find.byKey(MerchantApp.noAccessKey), findsNothing);
    });

    testWidgets('a pickup tap on the courier screen is cleared', (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(
          uid: 'c1',
          claims: {'role': 'courier', 'scope': 'merchant', 'merchantId': 'm1'},
        ),
      );

      expect(find.byType(CourierScreen), findsOneWidget);

      LuqmaPush.tapped.value = const LuqmaTap(
        kind: 'pickup',
        data: {'orderId': 'o-pickup'},
      );
      await tester.pumpAndSettle();

      expect(LuqmaPush.tapped.value, isNull);
    });
  });
}
