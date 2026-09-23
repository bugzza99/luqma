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

  Future<void> open(
    WidgetTester tester, {
    MenuItem item = shawarma,
    bool reducedMotion = false,
  }) async {
    choice = null;
    // A real phone, not the 800x600 test window: the sheet now stacks a 168 image above
    // the name, options and note, and on the default window rows fall off the bottom and
    // taps land outside them.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: LuqmaTheme.light,
        locale: const Locale('ar'),
        localizationsDelegates: LuqmaStrings.localizationsDelegates,
        supportedLocales: LuqmaStrings.supportedLocales,
        // Above the Navigator, not around `home`. The sheet is a route pushed onto that
        // Navigator rather than a child of the home widget, so a MediaQuery wrapped
        // around `home` — which is what the merchant screen's harness does, correctly,
        // for a screen — never reaches it, and the reduced-motion test would pass by
        // testing nothing.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
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

    // Breaks if the running total stops folding in the ticked extras — e.g. `_total`
    // reverting to `widget.item.price * _quantity`.
    testWidgets('grows by the price of a chosen extra', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(MerchantScreen.itemOptionKey('o1')));
      await tester.pumpAndSettle();

      expect(onButton('75 ج'), findsOneWidget);
    });

    testWidgets('an extra that costs nothing does not change it', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(MerchantScreen.itemOptionKey('o2')));
      await tester.pumpAndSettle();

      expect(onButton('60 ج'), findsOneWidget);
    });

    // Breaks if `_total` drops the `* _quantity`, or if the button reads
    // `widget.item.price` instead of `_total`.
    // The basket clamps a line at 99 without saying so; the sheet let the count run past
    // it, so the button could show the price of 150 portions for a basket that would hold
    // 99. The sheet stops where the basket does.
    testWidgets('stops where the basket does', (tester) async {
      await open(tester);

      for (var i = 0; i < 105; i++) {
        await tester.tap(find.byKey(MerchantScreen.itemMoreKey));
      }
      await tester.pumpAndSettle();

      expect(onButton('${60 * 99} ج'), findsOneWidget);
    });

    testWidgets('multiplies by how many', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(MerchantScreen.itemOptionKey('o1')));
      await tester.tap(find.byKey(MerchantScreen.itemMoreKey));
      await tester.pumpAndSettle();

      // (60 + 15) × 2.
      expect(onButton('150 ج'), findsOneWidget);
    });

    // Two prices on the button at once is the one thing this control must never do, and
    // it is exactly what the obvious animation does: an `AnimatedSwitcher` overlaps the
    // outgoing amount with the incoming one for the length of the fade, and the button
    // stays enabled the whole time. Somebody reading 60 while 75 fades up under it and
    // tapping is charged the number they did not read.
    //
    // So this walks the change frame by frame instead of settling it, and asserts the
    // invariant at every step: whatever the animation is doing, there is exactly one
    // amount on screen and it is the current one. Breaks the moment the total is put
    // back inside anything that keeps the previous value alive.
    testWidgets('never shows two amounts, on any frame of the change',
        (tester) async {
      await open(tester);

      await tester.tap(find.byKey(MerchantScreen.itemOptionKey('o1')));

      for (var elapsed = Duration.zero;
          elapsed < const Duration(milliseconds: 400);
          elapsed += const Duration(milliseconds: 16)) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(onButton('60 ج'), findsNothing,
            reason: 'the superseded amount is still on the button at $elapsed');
        expect(onButton('75 ج'), findsOneWidget,
            reason: 'the current amount is missing at $elapsed');
      }
    });

    // The pulse is the whole of what moves, so its absence is what reduced motion means
    // here. Breaks if the `disableAnimationsOf` branch is removed: the builder is then
    // constructed and paints its `begin` scale on the first frame.
    testWidgets('under reduced motion the amount does not move at all',
        (tester) async {
      await open(tester, reducedMotion: true);

      await tester.tap(find.byKey(MerchantScreen.itemOptionKey('o1')));
      await tester.pump();

      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(onButton('75 ج'), findsOneWidget);
    });
  });

  group('how many', () {
    testWidgets('starts at one', (tester) async {
      await open(tester);
      expect(find.byKey(MerchantScreen.itemQuantityKey), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    // Taking the last one out is removal, and removal belongs in the basket where the
    // line can be seen. Letting minus reach zero here would leave the customer staring
    // at a sheet for a dish they no longer want, with an "add" button under it. Breaks
    // if [_Footer] passes `onLess` unconditionally instead of gating it on `quantity > 1`.
    testWidgets('minus stops at one', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(MerchantScreen.itemLessKey));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });

    // A null `onPressed` is what makes the control look disabled and drop out of the
    // screen reader's action list at the same time. Breaks if [_Footer] passes `onLess`
    // unconditionally, or hides the floor by clamping inside the callback instead.
    testWidgets('the minus is disabled at one, enabled above it', (tester) async {
      await open(tester);

      IconButton less() =>
          tester.widget<IconButton>(find.byKey(MerchantScreen.itemLessKey));
      expect(less().onPressed, isNull);

      await tester.tap(find.byKey(MerchantScreen.itemMoreKey));
      await tester.pumpAndSettle();
      expect(less().onPressed, isNotNull);
    });

    testWidgets('what was chosen is what comes back', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(MerchantScreen.itemMoreKey));
      await tester.tap(find.byKey(MerchantScreen.itemMoreKey));
      await tester.pumpAndSettle();
      await add(tester);

      expect(choice!.quantity, 3);
    });
  });

  group('what comes back', () {
    testWidgets('carries only the extras that were ticked', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(MerchantScreen.itemOptionKey('o1')));
      await tester.pumpAndSettle();
      await add(tester);

      expect(choice!.options.single.id, 'o1');
    });

    testWidgets('an extra can be unticked again', (tester) async {
      await open(tester);

      await tester.tap(find.byKey(MerchantScreen.itemOptionKey('o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantScreen.itemOptionKey('o1')));
      await tester.pumpAndSettle();
      await add(tester);

      expect(choice!.options, isEmpty);
    });

    // The artboard's box is 22px; the finger aims at the row. Tapping the option's name
    // — the far end of the row from the box — must still toggle it. Breaks if the
    // gesture is bound to the checkbox widget instead of wrapping the whole row.
    testWidgets('the whole row toggles the extra, not just the box', (tester) async {
      await open(tester);

      await tester.tap(find.text('جبنة زيادة'));
      await tester.pumpAndSettle();

      expect(onButton('75 ج'), findsOneWidget);
    });

    testWidgets('carries the note', (tester) async {
      await open(tester);

      await tester.enterText(
        find.byKey(MerchantScreen.itemNoteKey),
        'حراق شوية',
      );
      await add(tester);

      expect(choice!.note, 'حراق شوية');
    });

    // An empty note and a note of three spaces are the same thing — no note. Keeping
    // the spaces would put a blank line on the kitchen's ticket. Breaks if `_choice`
    // stops calling `.trim()` before the `isEmpty` check.
    testWidgets('a note of nothing but spaces is no note', (tester) async {
      await open(tester);

      await tester.enterText(find.byKey(MerchantScreen.itemNoteKey), '   ');
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
    // Most dishes have none, and «إضافات» over empty space is a heading that says
    // nothing. Breaks if the block loses its `if (item.options.isNotEmpty)` guard.
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

      expect(find.text('إضافات'), findsNothing);
      expect(find.byKey(MerchantScreen.itemOptionsHeadingKey), findsNothing);
      expect(find.byKey(MerchantScreen.addToCartKey), findsOneWidget);
    });
  });

  group('the dish photograph', () {
    // The sheet shows the dish now, and on launch day there is no photo of it — so the
    // slot has to be a [LuqmaImage] that tints from the name, not a grey box. Breaks if
    // the head of the sheet is a plain coloured container.
    testWidgets('is a LuqmaImage that falls back to the name', (tester) async {
      await open(tester);

      final image = tester.widget<LuqmaImage>(
        find.byKey(MerchantScreen.itemImageKey),
      );
      expect(image.url, isNull);
      expect(image.name, 'شاورما فراخ');
    });
  });
}
