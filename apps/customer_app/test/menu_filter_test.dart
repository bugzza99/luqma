import 'package:customer_app/src/merchant/menu_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the menu filter', () {
    test('shows chips once there is a choice to make', () {
      expect(
        menuFilter(namedCategoryIds: const ['c1', 'c2'], chosen: null).showChips,
        isTrue,
      );
    });

    test('hides them when there is only one category, or none', () {
      expect(
        menuFilter(namedCategoryIds: const ['c1'], chosen: null).showChips,
        isFalse,
      );
      expect(
        menuFilter(namedCategoryIds: const [], chosen: null).showChips,
        isFalse,
      );
    });

    test('narrows the menu to the chip that was pressed', () {
      expect(
        menuFilter(namedCategoryIds: const ['c1', 'c2'], chosen: 'c2').selected,
        'c2',
      );
    });

    // The screen holds the chosen category in its own state and the categories arrive on
    // a live subscription, so the two can disagree at any moment.
    test('drops a selection whose category has gone', () {
      expect(
        menuFilter(namedCategoryIds: const ['c1', 'c2'], chosen: 'c9').selected,
        isNull,
      );
    });

    // The narrower version of the same trap, and the one that hides food: the category is
    // still there, so the selection is still valid — but its chip is not on screen any
    // more, and every dish outside it, including everything the merchant never filed under
    // a category at all, has silently gone with no control left to bring it back.
    test('drops a selection whose chip is no longer shown', () {
      expect(
        menuFilter(namedCategoryIds: const ['c1'], chosen: 'c1').selected,
        isNull,
      );
    });
  });
}
