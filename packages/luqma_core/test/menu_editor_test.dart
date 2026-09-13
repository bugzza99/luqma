import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// One editor, used by both MerchantApp and AdminApp.
///
/// The owner enters every menu personally during onboarding, and merchants edit their own
/// afterwards — the same job, so the same widget. The only difference is where
/// `merchantId` comes from, which is why it is a parameter and not a lookup.
void main() {
  const categories = [
    MenuCategory(id: 'c1', name: 'مشويات', sortOrder: 0),
    MenuCategory(id: 'c2', name: 'مشروبات', sortOrder: 1),
  ];

  final items = [
    const MenuItem(
      id: 'i1',
      merchantId: 'm1',
      categoryId: 'c1',
      name: 'فراخ مشوية',
      price: 12000,
    ),
    const MenuItem(
      id: 'i2',
      merchantId: 'm1',
      categoryId: 'c2',
      name: 'عصير مانجو',
      price: 2500,
      isAvailable: false,
    ),
  ];

  late FakeMenuRepository repository;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repository = FakeMenuRepository(categories: categories, items: items);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [menuRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Scaffold(body: MenuEditor(merchantId: 'm1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the categories and their items', (tester) async {
    await pump(tester);

    expect(find.text('مشويات'), findsOneWidget);
    expect(find.text('فراخ مشوية'), findsOneWidget);
    expect(find.text('عصير مانجو'), findsOneWidget);
  });

  testWidgets('shows prices in pounds, not the stored piastres', (tester) async {
    await pump(tester);

    expect(find.text('120 ج'), findsOneWidget);
    expect(find.text('25 ج'), findsOneWidget);
  });

  // An unavailable item stays on the menu for the merchant and disappears for the
  // customer, so the merchant needs to see at a glance which is which.
  testWidgets('marks an unavailable item', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('menu.unavailable.i2')), findsOneWidget);
    expect(find.byKey(const Key('menu.unavailable.i1')), findsNothing);
  });

  testWidgets('saves a new item', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(MenuEditor.addItemKey('c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(MenuEditor.nameFieldKey), 'كفتة');
    await tester.enterText(find.byKey(MenuEditor.priceFieldKey), '85');
    await tester.ensureVisible(find.byKey(MenuEditor.saveItemKey));
    await tester.tap(find.byKey(MenuEditor.saveItemKey));
    await tester.pumpAndSettle();

    final saved = repository.saved.last;
    expect(saved.name, 'كفتة');
    expect(saved.price, 8500, reason: 'typed in pounds, stored in piastres');
    expect(saved.categoryId, 'c1');
    expect(saved.merchantId, 'm1');
  });

  // The same fold as coupon codes, in the place it costs the most: a merchant whose
  // keyboard produces ٨٥ would otherwise be told their own price is invalid.
  testWidgets('accepts a price typed in Arabic-Indic digits', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(MenuEditor.addItemKey('c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(MenuEditor.nameFieldKey), 'كفتة');
    await tester.enterText(find.byKey(MenuEditor.priceFieldKey), '٨٥');
    await tester.ensureVisible(find.byKey(MenuEditor.saveItemKey));
    await tester.tap(find.byKey(MenuEditor.saveItemKey));
    await tester.pumpAndSettle();

    expect(repository.saved.last.price, 8500);
  });

  testWidgets('refuses an item with no name', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(MenuEditor.addItemKey('c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(MenuEditor.priceFieldKey), '85');
    await tester.ensureVisible(find.byKey(MenuEditor.saveItemKey));
    await tester.tap(find.byKey(MenuEditor.saveItemKey));
    await tester.pumpAndSettle();

    expect(repository.saved, isEmpty);
  });

  testWidgets('refuses an unreadable price rather than guessing at it', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(MenuEditor.addItemKey('c1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(MenuEditor.nameFieldKey), 'كفتة');
    await tester.enterText(find.byKey(MenuEditor.priceFieldKey), 'حاجة');
    await tester.ensureVisible(find.byKey(MenuEditor.saveItemKey));
    await tester.tap(find.byKey(MenuEditor.saveItemKey));
    await tester.pumpAndSettle();

    expect(repository.saved, isEmpty);
  });

  testWidgets('edits an existing item without creating a second one', (tester) async {
    await pump(tester);

    await tester.tap(find.text('فراخ مشوية'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(MenuEditor.priceFieldKey), '135');
    await tester.ensureVisible(find.byKey(MenuEditor.saveItemKey));
    await tester.tap(find.byKey(MenuEditor.saveItemKey));
    await tester.pumpAndSettle();

    expect(repository.saved.single.id, 'i1');
    expect(repository.saved.single.price, 13500);
  });

  testWidgets('an existing item opens with its current values', (tester) async {
    await pump(tester);

    await tester.tap(find.text('فراخ مشوية'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextFormField>(find.byKey(MenuEditor.priceFieldKey)).initialValue,
      '120',
    );
  });

  testWidgets('category chips filter the items', (tester) async {
    await pump(tester);

    // Initially both items are present when all categories are active
    expect(find.text('فراخ مشوية'), findsOneWidget);
    expect(find.text('عصير مانجو'), findsOneWidget);

    // Tapping category c1 filters to only c1 items
    await tester.tap(find.byKey(MenuEditor.categoryChipKey('c1')));
    await tester.pumpAndSettle();

    expect(find.text('فراخ مشوية'), findsOneWidget);
    expect(find.text('عصير مانجو'), findsNothing);

    // Tapping all categories restores all items
    await tester.tap(find.byKey(MenuEditor.allCategoriesChipKey));
    await tester.pumpAndSettle();

    expect(find.text('فراخ مشوية'), findsOneWidget);
    expect(find.text('عصير مانجو'), findsOneWidget);
  });

  testWidgets('toggling item availability switch directly updates the item', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(MenuEditor.itemAvailableSwitchKey('i1')));
    await tester.pumpAndSettle();

    expect(repository.saved.last.id, 'i1');
    expect(repository.saved.last.isAvailable, false);
  });

  testWidgets('deleting an existing item removes it from repository', (tester) async {
    await pump(tester);

    await tester.tap(find.text('فراخ مشوية'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(MenuEditor.deleteItemKey));
    await tester.tap(find.byKey(MenuEditor.deleteItemKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(MenuEditor.confirmDeleteKey));
    await tester.pumpAndSettle();

    expect(repository.deleted, contains('i1'));
  });

  testWidgets('adding a category with + فئة saves new category', (tester) async {
    await pump(tester);

    await tester.ensureVisible(find.byKey(MenuEditor.addCategoryKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MenuEditor.addCategoryKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(MenuEditor.categoryNameFieldKey), 'سندوتشات');
    await tester.tap(find.byKey(MenuEditor.saveCategoryKey));
    await tester.pumpAndSettle();

    expect(repository.categories.any((c) => c.name == 'سندوتشات'), isTrue);
  });
}
