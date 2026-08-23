import 'package:customer_app/src/home/section_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The home screen is composed by the owner, not by this app.
///
/// The boundary that keeps that from becoming server-driven UI: the app owns a fixed map
/// of section types to widgets, and the server only chooses which of them appear, in what
/// order, with what parameters. It cannot invent a section — and an entry naming one it
/// invented must not take the screen down.
void main() {
  HomeSection section(
    String type, {
    String key = 's1',
    int sortOrder = 0,
    bool isVisible = true,
    Map<String, dynamic> params = const {},
  }) =>
      HomeSection(
        key: key,
        type: type,
        titleAr: '',
        sortOrder: sortOrder,
        isVisible: isVisible,
        params: params,
      );

  group('what the app is willing to draw', () {
    test('every type the seed uses is registered', () {
      // These are the types firebase/seed/edku.json ships. A seeded home that renders
      // nothing is the failure this catches.
      for (final type in [
        'categoryChips',
        'adSlot',
        'homeKitchenToday',
        'mostOrdered',
        'merchantList',
      ]) {
        expect(HomeSectionRegistry.knows(type), isTrue, reason: type);
      }
    });

    test('a type nobody registered is not drawn', () {
      expect(HomeSectionRegistry.knows('somethingNew'), isFalse);
    });
  });

  group('deciding what goes on screen', () {
    test('sections come back in the order the owner set', () {
      final plan = HomeSectionRegistry.plan([
        section('mostOrdered', key: 'b', sortOrder: 2),
        section('categoryChips', key: 'a', sortOrder: 1),
        section('merchantList', key: 'c', sortOrder: 3),
      ]);

      expect(plan.map((s) => s.key), ['a', 'b', 'c']);
    });

    test('a hidden section is left out', () {
      final plan = HomeSectionRegistry.plan([
        section('categoryChips', key: 'a'),
        section('mostOrdered', key: 'b', isVisible: false),
      ]);

      expect(plan.map((s) => s.key), ['a']);
    });

    // The whole point of the boundary. A typo in AdminApp reaches every phone at once;
    // it must cost that section, not the screen.
    test('an unknown type is skipped and the rest still render', () {
      final plan = HomeSectionRegistry.plan([
        section('categoryChips', key: 'a'),
        section('typoSection', key: 'bad', sortOrder: 1),
        section('merchantList', key: 'c', sortOrder: 2),
      ]);

      expect(plan.map((s) => s.key), ['a', 'c']);
    });

    test('a home with nothing usable in it is empty, not broken', () {
      expect(HomeSectionRegistry.plan([section('typoSection')]), isEmpty);
    });

    test('two sections of the same type are both drawn', () {
      // Two ad slots, one near the top and one further down, is a normal arrangement.
      final plan = HomeSectionRegistry.plan([
        section('adSlot', key: 'top', sortOrder: 0),
        section('merchantList', key: 'list', sortOrder: 1),
        section('adSlot', key: 'mid', sortOrder: 2),
      ]);

      expect(plan.map((s) => s.key), ['top', 'list', 'mid']);
    });
  });

  group('building the widgets', () {
    testWidgets('a known section builds something', (tester) async {
      final widget = HomeSectionRegistry.build(section('categoryChips'));
      expect(widget, isNotNull);
    });

    testWidgets('an unknown section builds nothing at all', (tester) async {
      // Not an error widget, not a placeholder — a section the app cannot draw should
      // leave no trace on the screen.
      expect(HomeSectionRegistry.build(section('typoSection')), isNull);
    });

    testWidgets('a section reads its parameters', (tester) async {
      final built = HomeSectionRegistry.build(
        section('adSlot', params: const {'maxAds': 3, 'rotationSeconds': 6}),
      );
      expect(built, isA<Widget>());
    });
  });
}
