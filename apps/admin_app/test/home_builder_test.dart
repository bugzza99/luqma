import 'package:admin_app/src/home_builder/home_builder_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Arranging the customer's home screen without shipping an app.
///
/// The boundary this screen enforces is the whole of "dynamic": the owner picks which
/// registered blocks appear, in what order, and whether they are visible. They cannot
/// describe a *new kind* of block — the app owns the map of types to widgets, and that
/// is what keeps this from becoming server-driven UI.
void main() {
  HomeSection section({
    String key = 'list',
    String type = 'merchantList',
    int sortOrder = 0,
    bool isVisible = true,
  }) =>
      HomeSection(
        key: key,
        type: type,
        sortOrder: sortOrder,
        isVisible: isVisible,
        cityId: 'edku',
      );

  late FakeHomeSectionRepository sections;

  Future<void> pump(WidgetTester tester, {List<HomeSection> seed = const []}) async {
    sections = FakeHomeSectionRepository(seed: seed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentIdentityProvider.overrideWith(
            (ref) => Stream.value(
              const LuqmaIdentity(uid: 'admin1', claims: {'admin': true}),
            ),
          ),
          homeSectionRepositoryProvider.overrideWithValue(sections),
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
            child: HomeBuilderScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('what is on the home', () {
    testWidgets('every block, in the order the customer sees them', (tester) async {
      await pump(tester, seed: [
        section(key: 'list', sortOrder: 1),
        section(key: 'chips', type: 'categoryChips', sortOrder: 0),
      ]);

      final chips = tester.getTopLeft(find.byKey(HomeBuilderScreen.rowKey('chips'))).dy;
      final list = tester.getTopLeft(find.byKey(HomeBuilderScreen.rowKey('list'))).dy;
      expect(chips, lessThan(list));
    });

    // A hidden block is not a deleted one. Hiding the home-kitchen band on a day nobody
    // is cooking and putting it back tomorrow must not lose its settings.
    testWidgets('a hidden block is still listed, marked', (tester) async {
      await pump(tester, seed: [section(isVisible: false)]);

      expect(find.byKey(HomeBuilderScreen.rowKey('list')), findsOneWidget);
      expect(find.byKey(HomeBuilderScreen.hiddenKey('list')), findsOneWidget);
    });

    testWidgets('an empty home says so', (tester) async {
      await pump(tester);
      expect(find.byKey(HomeBuilderScreen.emptyKey), findsOneWidget);
    });

    // A block whose type this build does not know is an entry somebody mistyped. It has
    // to be visible here — it renders as nothing on the customer's phone, and an admin
    // who cannot see it cannot fix it.
    testWidgets('a type the app does not know is flagged, not hidden', (tester) async {
      await pump(tester, seed: [section(key: 'oops', type: 'bannerz')]);

      expect(find.byKey(HomeBuilderScreen.rowKey('oops')), findsOneWidget);
      expect(find.byKey(HomeBuilderScreen.unknownKey('oops')), findsOneWidget);
    });
  });

  group('changing it', () {
    testWidgets('hiding a block writes it away', (tester) async {
      await pump(tester, seed: [section()]);

      await tester.tap(find.byKey(HomeBuilderScreen.visibilityKey('list')));
      await tester.pumpAndSettle();

      expect(sections['list']!.isVisible, isFalse);
    });

    testWidgets('showing it again brings it back', (tester) async {
      await pump(tester, seed: [section(isVisible: false)]);

      await tester.tap(find.byKey(HomeBuilderScreen.visibilityKey('list')));
      await tester.pumpAndSettle();

      expect(sections['list']!.isVisible, isTrue);
    });

    testWidgets('moving a block up changes what the customer sees first',
        (tester) async {
      await pump(tester, seed: [
        section(key: 'chips', type: 'categoryChips', sortOrder: 0),
        section(key: 'list', sortOrder: 1),
      ]);

      await tester.tap(find.byKey(HomeBuilderScreen.upKey('list')));
      await tester.pumpAndSettle();

      expect(sections['list']!.sortOrder, lessThan(sections['chips']!.sortOrder));
    });

    testWidgets('the first block cannot move up', (tester) async {
      await pump(tester, seed: [section(key: 'chips', sortOrder: 0)]);

      final button = tester.widget<IconButton>(
        find.byKey(HomeBuilderScreen.upKey('chips')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the last block cannot move down', (tester) async {
      await pump(tester, seed: [section(key: 'chips', sortOrder: 0)]);

      final button = tester.widget<IconButton>(
        find.byKey(HomeBuilderScreen.downKey('chips')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('adding one', () {
    // Only the types the app actually registered. The owner picks from a list rather
    // than typing a string, which is the boundary that keeps a typo off every phone.
    testWidgets('offers only types the app can draw', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(HomeBuilderScreen.addKey));
      await tester.pumpAndSettle();

      for (final type in HomeBuilderScreen.knownTypes) {
        expect(find.byKey(HomeBuilderScreen.typeKey(type)), findsOneWidget);
      }
    });

    testWidgets('a new block lands at the bottom, visible', (tester) async {
      await pump(tester, seed: [section(key: 'chips', sortOrder: 0)]);

      await tester.tap(find.byKey(HomeBuilderScreen.addKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeBuilderScreen.typeKey('adSlot')));
      await tester.pumpAndSettle();

      final added = sections.all.firstWhere((s) => s.type == 'adSlot');
      expect(added.isVisible, isTrue);
      expect(added.sortOrder, greaterThan(0));
    });

    // Two ad slots on one screen is a real arrangement — one near the top, one further
    // down — so a second block of the same type needs its own key.
    testWidgets('a second block of the same type gets its own key', (tester) async {
      await pump(tester, seed: [section(key: 'adSlot', type: 'adSlot')]);

      await tester.tap(find.byKey(HomeBuilderScreen.addKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeBuilderScreen.typeKey('adSlot')));
      await tester.pumpAndSettle();

      final slots = sections.all.where((s) => s.type == 'adSlot').toList();
      expect(slots, hasLength(2));
      expect(slots[0].key, isNot(slots[1].key));
    });
  });
}
