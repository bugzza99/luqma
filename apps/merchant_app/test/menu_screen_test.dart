import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/menu/menu_screen.dart';

/// The merchant's own menu screen (M03).
void main() {
  const categories = [
    MenuCategory(id: 'c1', name: 'مشويات', sortOrder: 0),
  ];

  final items = [
    const MenuItem(
      id: 'i1',
      merchantId: 'm1',
      categoryId: 'c1',
      name: 'فراخ مشوية',
      price: 12000,
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    String? merchantId = 'm1',
  }) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = FakeMenuRepository(categories: categories, items: items);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(
            FakeAuthService(
              restoring: LuqmaIdentity(
                uid: 'merchant-owner',
                claims: {
                  'role': 'owner',
                  'scope': 'merchant',
                  'merchantId': ?merchantId,
                },
              ),
            ),
          ),
          menuRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MenuScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('when account has no merchant, shows unlinked message', (tester) async {
    await pump(tester, merchantId: null);

    expect(find.byKey(MenuScreen.noMerchantKey), findsOneWidget);
    expect(find.text('الحساب ده مش مربوط بمطعم'), findsOneWidget);
    expect(find.byType(MenuEditor), findsNothing);
  });

  testWidgets('when account has merchant, shows MenuEditor and title القائمة', (tester) async {
    await pump(tester, merchantId: 'm1');

    expect(find.byType(MenuEditor), findsOneWidget);
    expect(find.text('القائمة'), findsOneWidget);
  });
}
