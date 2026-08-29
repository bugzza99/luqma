import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/shop/busy_toggle.dart';
import 'package:merchant_app/src/shop/shop_screen.dart';

/// The shop tab when the shop cannot be loaded.
///
/// Everything on this screen was gated on `merchant != null`, and the merchant came from
/// `ref.watch(merchantProvider(id)).value` — which is null while loading *and* null on
/// failure. So a dropped connection drew an empty page: no identity, no rating, no
/// billing, and `BusyToggle` collapsed to nothing.
///
/// That last part is what makes it worth a test rather than a shrug. The busy control is
/// how a merchant stops orders during a rush. A merchant who cannot see it does not
/// think "the connection is down"; they think the shop is fine, and orders keep
/// arriving at a kitchen that has no way to say stop.
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
  );

  Future<void> pump(
    WidgetTester tester, {
    Failure? failure,
    Failure? saveFailure,
  }) async {
    // A phone, not the runner's 800x600 default — that window is wider than it is tall
    // and unlike anything this ships on.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(
            FakeAuthService(
              restoring: const LuqmaIdentity(
                uid: 'owner1',
                claims: {'role': 'owner', 'scope': 'merchant', 'merchantId': 'm1'},
              ),
            ),
          ),
          merchantRepositoryProvider.overrideWithValue(
            FakeMerchantRepository(
              seed: const [shop],
              failure: failure,
              saveFailure: saveFailure,
            ),
          ),
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
            child: ShopScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the shop that loads shows its name and the busy control',
      (tester) async {
    await pump(tester);

    expect(find.text('مطعم الشاطئ'), findsOneWidget);
    expect(find.byType(BusyToggle), findsOneWidget);
    expect(find.byType(LuqmaErrorView), findsNothing);
  });

  testWidgets('a shop that will not load says so, with a way to try again',
      (tester) async {
    await pump(tester, failure: const OfflineFailure());

    expect(find.byType(LuqmaErrorView), findsOneWidget,
        reason: 'an empty page is indistinguishable from a shop with nothing in it');
    expect(find.text('مطعم الشاطئ'), findsNothing);
  });

  // The cover is drawn from the picked file the moment it uploads, and the `Result` of
  // the save that follows was thrown away. So a save that failed looked exactly like one
  // that worked: the merchant sees their new cover, closes the app, and the row still
  // carries the old id. The customer keeps seeing the tinted placeholder, and nobody
  // involved has any reason to think anything went wrong.
  testWidgets('a cover that could not be saved does not stay on the screen',
      (tester) async {
    await pump(tester, saveFailure: const OfflineFailure());

    // Straight through the real handler: the picker itself needs a file, and what is
    // under test is what the screen does with the upload rather than the picking.
    final picker = tester.widget<MediaPicker>(find.byType(MediaPicker));
    picker.onUploaded(const Media(
      id: 'md1',
      kind: MediaKind.merchantCover,
      url: 'https://example.test/cover.jpg',
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('جرّب تاني'), findsOneWidget);
  });
}
