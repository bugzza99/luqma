import 'package:customer_app/src/orders/order_time.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The orders list's timestamps, in the app's own voice: a 12-hour clock with a ص/م
/// marker, Western digits, and a relative day that only names weekdays for the last week.
void main() {
  final s = lookupLuqmaStrings(const Locale('ar'));

  group('formatClockTime', () {
    test('an evening time is 12-hour with the م marker', () {
      expect(formatClockTime(DateTime(2026, 8, 20, 20, 45), s), '8:45 م');
    });

    test('a morning time takes the ص marker and pads the minutes', () {
      expect(formatClockTime(DateTime(2026, 8, 20, 9, 5), s), '9:05 ص');
    });

    test('noon reads 12 م and midnight reads 12 ص', () {
      expect(formatClockTime(DateTime(2026, 8, 20, 12), s), '12:00 م');
      expect(formatClockTime(DateTime(2026, 8, 20, 0, 30), s), '12:30 ص');
    });
  });

  group('formatOrderDay', () {
    // 2026-08-27 is a Thursday.
    final now = DateTime(2026, 8, 27, 20);

    test('the same calendar day is النهارده', () {
      expect(formatOrderDay(DateTime(2026, 8, 27, 9), now, s), 'النهارده');
    });

    test('the day before is امبارح', () {
      expect(formatOrderDay(DateTime(2026, 8, 26, 21, 20), now, s), 'امبارح');
    });

    test('within the last week is the colloquial weekday name', () {
      // 2026-08-24 is a Monday.
      expect(formatOrderDay(DateTime(2026, 8, 24, 12), now, s), 'الاتنين');
    });

    test('older than a week collapses to a plain numeric date', () {
      expect(formatOrderDay(DateTime(2026, 8, 1, 12), now, s), '1/8/2026');
    });
  });
}
