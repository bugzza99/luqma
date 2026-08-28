import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Today's home-cooked meal.
///
/// A different unit from a menu item, and the difference is the whole of what makes home
/// kitchens work: somebody cooks a fixed number of portions once, and when they are gone
/// they are gone. A menu item is a promise to cook on demand; this is a count.
void main() {
  DailyMeal meal({
    String date = '2026-08-23',
    int totalQty = 20,
    int remainingQty = 8,
    DailyMealStatus status = DailyMealStatus.published,
    int pickupStart = 13 * 60,
    int pickupEnd = 16 * 60,
    DeliveryOption deliveryOption = DeliveryOption.pickup,
  }) =>
      DailyMeal(
        id: 'd1',
        merchantId: 'm1',
        cityId: 'edku',
        name: 'محشي كرنب',
        description: 'بيتي، اتعمل النهارده',
        price: 9000,
        date: date,
        totalQty: totalQty,
        remainingQty: remainingQty,
        pickupWindowStart: pickupStart,
        pickupWindowEnd: pickupEnd,
        deliveryOption: deliveryOption,
        status: status,
      );

  group('the day', () {
    // A calendar day, not an instant. "Today's meals" is an equality query, and an
    // equality query on a timestamp matches one microsecond — never a day.
    test('is a plain day key', () {
      expect(DailyMeal.dayKeyOf(DateTime(2026, 8, 23, 19, 30)), '2026-08-23');
    });

    test('pads so the keys sort and compare as strings', () {
      expect(DailyMeal.dayKeyOf(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('a meal knows whether it is today\'s', () {
      expect(meal().isFor(DateTime(2026, 8, 23, 11)), isTrue);
      expect(meal().isFor(DateTime(2026, 8, 24, 11)), isFalse);
    });
  });

  group('what is left', () {
    test('sold out is derived from the count, never stored', () {
      expect(meal(remainingQty: 0).isSoldOut, isTrue);
      expect(meal(remainingQty: 1).isSoldOut, isFalse);
    });

    // A count that went negative means two people reserved the last portion. The screen
    // must read that as sold out rather than as "-1 left".
    test('a count below zero still reads as sold out', () {
      expect(meal(remainingQty: -1).isSoldOut, isTrue);
      expect(meal(remainingQty: -1).remainingOrZero, 0);
    });

    test('how far through it is', () {
      expect(meal(totalQty: 20, remainingQty: 5).fractionLeft, 0.25);
    });

    // A meal published with no quantity is a bug upstream, and dividing by it is a crash
    // on the customer's home screen.
    test('a meal with no portions at all does not divide by zero', () {
      expect(meal(totalQty: 0, remainingQty: 0).fractionLeft, 0);
    });
  });

  group('whether it can still be ordered', () {
    final duringWindow = DateTime(2026, 8, 23, 11);

    test('a published meal with portions left can', () {
      expect(meal().canBeOrderedAt(duringWindow), isTrue);
    });

    test('a draft cannot — nobody has said it is happening', () {
      expect(
        meal(status: DailyMealStatus.draft).canBeOrderedAt(duringWindow),
        isFalse,
      );
    });

    test('a sold-out meal cannot', () {
      expect(meal(remainingQty: 0).canBeOrderedAt(duringWindow), isFalse);
    });

    test('yesterday\'s meal cannot', () {
      expect(meal().canBeOrderedAt(DateTime(2026, 8, 24, 11)), isFalse);
    });

    // Ordering at half past three for a window that closes at four is somebody who will
    // not make it. The kitchen has to stop taking orders before it stops serving.
    test('not once the collection window has closed', () {
      expect(meal().canBeOrderedAt(DateTime(2026, 8, 23, 16, 1)), isFalse);
    });

    test('a closed meal cannot, whatever the count says', () {
      expect(
        meal(status: DailyMealStatus.closed, remainingQty: 10)
            .canBeOrderedAt(duringWindow),
        isFalse,
      );
    });
  });

  group('serialization', () {
    test('survives a round trip', () {
      final restored = DailyMeal.fromJson(meal().toJson());

      expect(restored.name, 'محشي كرنب');
      expect(restored.remainingQty, 8);
      expect(restored.pickupWindowEnd, 16 * 60);
      expect(restored.deliveryOption, DeliveryOption.pickup);
      expect(restored.status, DailyMealStatus.published);
    });

    // An option added on the server before this build knew about it must not crash a
    // customer's home screen.
    test('an unknown delivery option falls back rather than throwing', () {
      final json = meal().toJson()..['deliveryOption'] = 'teleportation';

      expect(DailyMeal.fromJson(json).deliveryOption, DeliveryOption.pickup);
    });
  });
}
