import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The other half of a notification: what happens when somebody taps it.
///
/// `LuqmaPush` has written the tapped order to a notifier since Phase 4 and nothing
/// anywhere read it, so the alarm rang, the merchant tapped it, and the app came forward
/// on whatever screen it was last on. These tests are the reader.
void main() {
  setUp(() => LuqmaPush.tappedOrder.value = null);
  tearDown(() => LuqmaPush.tappedOrder.value = null);

  Future<List<String>> pump(WidgetTester tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LuqmaTappedOrder(
          onOpen: opened.add,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    return opened;
  }

  testWidgets('an order tapped while the app was dead is opened on the first frame',
      (tester) async {
    // The launch case, and the one that cannot be covered by a listener alone: the tap
    // is recorded by `getInitialMessage` before any of this app's widgets exist.
    LuqmaPush.tappedOrder.value = 'order-from-a-cold-start';

    final opened = await pump(tester);

    expect(opened, ['order-from-a-cold-start']);
  });

  testWidgets('an order tapped while the app is running is opened', (tester) async {
    final opened = await pump(tester);

    LuqmaPush.tappedOrder.value = 'order-while-alive';
    await tester.pump();

    expect(opened, ['order-while-alive']);
  });

  testWidgets('the same order is not opened twice by a rebuild', (tester) async {
    // Taking the value rather than watching it. A shell rebuilds on every tab switch,
    // and an order that reopens itself each time is a screen nobody can leave.
    final opened = await pump(tester);

    LuqmaPush.tappedOrder.value = 'order-once';
    await tester.pump();
    await tester.pump();

    expect(opened, ['order-once']);
  });

  testWidgets('tapping the same order again does open it again', (tester) async {
    // The consequence of taking rather than remembering: two notifications about one
    // order are two requests to see it, and the second must not be swallowed as a
    // duplicate of the first.
    final opened = await pump(tester);

    LuqmaPush.tappedOrder.value = 'order-twice';
    await tester.pump();
    LuqmaPush.tappedOrder.value = 'order-twice';
    await tester.pump();

    expect(opened, ['order-twice', 'order-twice']);
  });

  testWidgets('nothing is opened when no notification was tapped', (tester) async {
    final opened = await pump(tester);
    await tester.pump();

    expect(opened, isEmpty);
  });

  testWidgets('a tap after the widget is gone opens nothing', (tester) async {
    final opened = await pump(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    LuqmaPush.tappedOrder.value = 'order-after-dispose';
    await tester.pump();

    expect(opened, isEmpty);
  });
}
