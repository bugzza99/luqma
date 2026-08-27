import 'package:admin_app/src/dashboard/module_grid_screen.dart';
import 'package:admin_app/src/shell/layout.dart';
import 'package:flutter/material.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// AdminApp runs on the owner's phone and, from the same code, in a browser on a laptop.
///
/// That is not polish. The launch plan has the owner entering roughly six hundred menu
/// items personally, and the difference between typing those on a phone keyboard and on a
/// real one is measured in weeks.
void main() {
  group('choosing a layout', () {
    test('a phone gets the compact layout', () {
      expect(AdminLayout.forWidth(360), AdminLayout.compact);
      expect(AdminLayout.forWidth(599), AdminLayout.compact);
    });

    test('a tablet gets a navigation rail but still one pane', () {
      expect(AdminLayout.forWidth(600), AdminLayout.medium);
      expect(AdminLayout.forWidth(839), AdminLayout.medium);
    });

    test('a laptop gets two panes', () {
      expect(AdminLayout.forWidth(840), AdminLayout.expanded);
      expect(AdminLayout.forWidth(1920), AdminLayout.expanded);
    });

    test('only the expanded layout shows both panes at once', () {
      expect(AdminLayout.compact.showsTwoPanes, isFalse);
      expect(AdminLayout.medium.showsTwoPanes, isFalse);
      expect(AdminLayout.expanded.showsTwoPanes, isTrue);
    });

    test('the compact layout is the only one with a bottom bar', () {
      expect(AdminLayout.compact.usesBottomNav, isTrue);
      expect(AdminLayout.medium.usesBottomNav, isFalse);
      expect(AdminLayout.expanded.usesBottomNav, isFalse);
    });
  });

  group('the shell', () {
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AdminShell(
              modules: const [
                AdminModule(label: 'المطاعم', icon: Icons.store, route: '/merchants'),
                AdminModule(label: 'المناطق', icon: Icons.map, route: '/zones'),
              ],
              currentRoute: '/merchants',
              onDestination: (_) {},
              child: const Text('المحتوى'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // No bottom bar at all any more. There are fourteen modules and `NavigationBar` is
    // designed for three to five; eleven of them was already a row of unreadable
    // slivers. On a phone the grid at `/` is the navigation.
    testWidgets('a phone shows neither bar nor rail', (tester) async {
      await pumpAt(tester, const Size(400, 800));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    });

    // The rail stays on a desktop, where fourteen labelled rows are readable and a grid
    // would mean a trip home between every module.
    testWidgets('a laptop shows a rail and no bottom bar', (tester) async {
      await pumpAt(tester, const Size(1400, 900));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    // The same widget tree either way — the shell rearranges its chrome rather than each
    // screen being written twice.
    testWidgets('the content is the same at both sizes', (tester) async {
      await pumpAt(tester, const Size(400, 800));
      expect(find.text('المحتوى'), findsOneWidget);

      await pumpAt(tester, const Size(1400, 900));
      expect(find.text('المحتوى'), findsOneWidget);
    });

    // On a phone the shell carries no navigation at all — the grid at `/` is it, and it
    // is one tap away from every module and one back from any of them. What the shell
    // still owes a phone is the content, whole.
    testWidgets('a phone gets the content and nothing in its way', (tester) async {
      await pumpAt(tester, const Size(400, 800));

      expect(find.text('المحتوى'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('every module is reachable from the rail on a laptop',
        (tester) async {
      await pumpAt(tester, const Size(1400, 900));

      expect(find.text('المطاعم'), findsWidgets);
      expect(find.text('المناطق'), findsWidgets);
    });
  });

  group('long-form content on a wide screen', () {
    // Text running the full width of a 1920px browser is unreadable, and a form whose
    // fields are a metre wide is worse. The shell caps it rather than each screen
    // remembering to.
    test('is capped rather than run edge to edge', () {
      expect(AdminLayout.contentWidthFor(1920), lessThan(1920));
      expect(AdminLayout.contentWidthFor(1920), AdminLayout.maxContentWidth);
    });

    test('a narrow screen uses everything it has', () {
      expect(AdminLayout.contentWidthFor(400), 400);
    });
  });
}
