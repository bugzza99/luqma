import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Every tabbed shell in the product shows the next tab in place — an `IndexedStack`,
/// never a pushed route — so scroll position and loaded data survive the switch. What
/// that costs: once somebody is on a tab other than the first, the root Navigator's
/// stack still holds exactly one entry, the shell itself. System back finds nothing to
/// pop, and Android falls through to closing the app, which reads exactly like a crash
/// to someone who meant to go back one tab.
void main() {
  Widget harness({required int index, required VoidCallback onHome}) {
    return MaterialApp(
      home: LuqmaTabPopScope(
        currentIndex: index,
        onHome: onHome,
        child: const Scaffold(body: Text('الشاشة')),
      ),
    );
  }

  group('LuqmaTabPopScope', () {
    testWidgets('back on a tab other than the first returns to it, not out of the app',
        (tester) async {
      var wentHome = false;
      await tester.pumpWidget(harness(index: 2, onHome: () => wentHome = true));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(wentHome, isTrue);
      // The app is still here — the pop was intercepted rather than let through.
      expect(find.text('الشاشة'), findsOneWidget);
    });

    testWidgets('back on the first tab is let through rather than intercepted',
        (tester) async {
      var wentHome = false;
      await tester.pumpWidget(harness(index: 0, onHome: () => wentHome = true));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Nothing above this route to pop, so nothing happens on screen — the point is
      // that `onHome` was never called for a tab that is already home.
      expect(wentHome, isFalse);
    });

    testWidgets('a second tab set at build time behaves the same as switching to it',
        (tester) async {
      var wentHome = false;
      await tester.pumpWidget(harness(index: 1, onHome: () => wentHome = true));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(wentHome, isTrue);
    });
  });
}
