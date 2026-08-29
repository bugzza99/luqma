import 'package:customer_app/src/merchant/item_sheet.dart';
import 'package:customer_app/src/merchant/merchant_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The one place a dish becomes a decision: extras, how many, and a word to the kitchen.
void main() {
  const shawarma = MenuItem(
    id: 'i1',
    merchantId: 'm1',
    categoryId: 'c1',
    name: 'شاورما فراخ',
    price: 6000,
    options: [
      MenuOption(id: 'o1', name: 'جبنة زيادة', price: 1500),
      MenuOption(id: 'o2', name: 'من غير مخلل'),
    ],
  );

  late ItemChoice? choice;

  Future<void> open(WidgetTester tester, {MenuItem item = shawarma}) async {
    choice = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: LuqmaTheme.light,
        locale: const Locale('ar'),
        localizationsDelegates: LuqmaStrings.localizationsDelegates,
        supportedLocales: LuqmaStrings.supportedLocales,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    choice = await showModalBottomSheet<ItemChoice>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ItemSheet(item: item),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Text inside the add button, so a price shown elsewhere on the sheet cannot stand
  /// in for the one the customer is about to commit to.
  Finder onButton(String text) => find.descendant(
        of: find.byKey(MerchantScreen.addToCartKey),
        matching: find.textContaining(text),
      );

  Future<void> add(WidgetTester tester) async {
    await tester.tap(find.byKey(MerchantScreen.addToCartKey));
    await tester.pumpAndSettle();
  }

  group('the price on the button', () {
    // The button is the last thing read before committing. A number there that is not
    // the number charged is the one lie the whole screen must never tell.
    testWidgets('starts at the price of the dish', (tester) async {
      await open(tester);
      expect(onButton('60 ج'), findsOneWidget);
    });

    testWidgets('grows by the price of a chosen extra', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('itemSheet.option.o1')));
      await tester.pumpAndSettle();

      expect(onButton('75 ج'), findsOneWidget);
    });

    testWidgets('an extra that costs nothing does not change it', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('itemSheet.option.o2')));
      await tester.pumpAndSettle();

      expect(onButton('60 ج'), findsOneWidget);
    });

    testWidgets('multiplies by how many', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('itemSheet.option.o1')));
      await tester.tap(find.byKey(const Key('itemSheet.more')));
      await tester.pumpAndSettle();

      // (60 + 15) × 2.
      expect(onButton('150 ج'), findsOneWidget);
    });
  });

  group('how many', () {
    testWidgets('starts at one', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('itemSheet.quantity')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    // Taking the last one out is removal, and removal belongs in the basket where the
    // line can be seen. Letting minus reach zero here would leave the customer staring
    // at a sheet for a dish they no longer want, with an "add" button under it.
    testWidgets('minus stops at one', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('itemSheet.less')));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('what was chosen is what comes back', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('itemSheet.more')));
      await tester.tap(find.byKey(const Key('itemSheet.more')));
      await tester.pumpAndSettle();
      await add(tester);

      expect(choice!.quantity, 3);
    });
  });

  group('what comes back', () {
    testWidgets('carries only the extras that were ticked', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('itemSheet.option.o1')));
      await tester.pumpAndSettle();
      await add(tester);

      expect(choice!.options.single.id, 'o1');
    });

    testWidgets('an extra can be unticked again', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(const Key('itemSheet.option.o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('itemSheet.option.o1')));
      await tester.pumpAndSettle();
      await add(tester);

      expect(choice!.options, isEmpty);
    });

    testWidgets('carries the note', (tester) async {
      await open(tester);

      await tester.enterText(
        find.byKey(const Key('itemSheet.note')),
        'حراق شوية',
      );
      await add(tester);

      expect(choice!.note, 'حراق شوية');
    });

    // An empty note and a note of three spaces are the same thing — no note. Keeping
    // the spaces would put a blank line on the kitchen's ticket.
    testWidgets('a note of nothing but spaces is no note', (tester) async {
      await open(tester);

      await tester.enterText(find.byKey(const Key('itemSheet.note')), '   ');
      await add(tester);

      expect(choice!.note, isNull);
    });

    testWidgets('dismissing the sheet chooses nothing', (tester) async {
      await open(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(choice, isNull);
    });
  });

  group('a dish with no extras', () {
    testWidgets('shows no extras section', (tester) async {
      await open(
        tester,
        item: const MenuItem(
          id: 'i2',
          merchantId: 'm1',
          categoryId: 'c1',
          name: 'عيش',
          price: 500,
        ),
      );

      expect(find.text('الإضافات'), findsNothing);
      expect(find.byKey(MerchantScreen.addToCartKey), findsOneWidget);
    });
  });
}
