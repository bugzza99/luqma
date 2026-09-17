import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  final strings = lookupLuqmaStrings(const Locale('ar'));

  group('luqmaOrderDay', () {
    // 2026-08-27 is a Thursday.
    final now = DateTime(2026, 8, 27, 20);

    test('same calendar day resolves to النهارده', () {
      expect(luqmaOrderDay(DateTime(2026, 8, 27, 10), now, strings), 'النهارده');
    });

    test('day before resolves to امبارح', () {
      expect(luqmaOrderDay(DateTime(2026, 8, 26, 22), now, strings), 'امبارح');
    });

    test('within last week resolves to weekday name', () {
      // 2026-08-24 is Monday
      expect(luqmaOrderDay(DateTime(2026, 8, 24, 14), now, strings), 'الاتنين');
    });

    test('more than a week ago collapses to numeric date', () {
      expect(luqmaOrderDay(DateTime(2026, 8, 1, 10), now, strings), '1/8/2026');
    });
  });

  group('luqmaMonthName', () {
    test('resolves Arabic month names', () {
      expect(luqmaMonthName(1), 'يناير');
      expect(luqmaMonthName(8), 'أغسطس');
      expect(luqmaMonthName(12), 'ديسمبر');
      expect(luqmaMonthName(0), '');
      expect(luqmaMonthName(13), '');
    });
  });
}
