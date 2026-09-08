import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Arabic has six plural categories, not two. Writing "$n طلبات" — which is what a
/// simple string map forces you to do — is wrong for five of the six. These tests pin
/// the forms so a translator or a hurried edit cannot quietly break them.
void main() {
  late LuqmaStrings s;

  setUp(() async {
    s = await LuqmaStrings.delegate.load(const Locale('ar'));
  });

  group('orders', () {
    test('none', () => expect(s.orderCount(0), 'لا توجد طلبات'));
    test('one', () => expect(s.orderCount(1), 'طلب واحد'));
    test('two', () => expect(s.orderCount(2), 'طلبان'));
    test('a few', () => expect(s.orderCount(3), '3 طلبات'));
    test('a few, upper end', () => expect(s.orderCount(10), '10 طلبات'));
    test('many', () => expect(s.orderCount(11), '11 طلبًا'));
    test('many, upper end', () => expect(s.orderCount(99), '99 طلبًا'));
    test('a round hundred', () => expect(s.orderCount(100), '100 طلب'));
  });

  group('portions left on a home-cooked meal', () {
    test('sold out', () => expect(s.portionsLeft(0), 'خلصت'));
    test('one', () => expect(s.portionsLeft(1), 'فاضل طبق واحد'));
    test('two', () => expect(s.portionsLeft(2), 'فاضل طبقان'));
    test('a few', () => expect(s.portionsLeft(6), 'فاضل 6 أطباق'));
    test('many', () => expect(s.portionsLeft(15), 'فاضل 15 طبقًا'));
  });

  group('minutes', () {
    test('one', () => expect(s.minutes(1), 'دقيقة'));
    test('two', () => expect(s.minutes(2), 'دقيقتان'));
    test('a few', () => expect(s.minutes(5), '5 دقائق'));
    test('many', () => expect(s.minutes(25), '25 دقيقة'));
  });

  group('ratings behind a merchant average', () {
    test('none', () => expect(s.ratingsCount(0), 'مفيش تقييمات'));
    test('one', () => expect(s.ratingsCount(1), 'تقييم واحد'));
    test('two', () => expect(s.ratingsCount(2), 'تقييمين'));
    test('a few', () => expect(s.ratingsCount(7), '7 تقييمات'));
    test('a few, upper end', () => expect(s.ratingsCount(10), '10 تقييمات'));
    test('many', () => expect(s.ratingsCount(38), '38 تقييم'));
    test('a round hundred', () => expect(s.ratingsCount(100), '100 تقييم'));
  });

  group('distinct things in the basket', () {
    test('none', () => expect(s.itemCount(0), 'مفيش أصناف'));
    test('one', () => expect(s.itemCount(1), 'صنف واحد'));
    // The artboard writes "2 صنف"; two of anything in Arabic is a dual, not a bare count.
    test('two', () => expect(s.itemCount(2), 'صنفين'));
    test('a few', () => expect(s.itemCount(3), '3 أصناف'));
    test('many', () => expect(s.itemCount(11), '11 صنف'));
  });

  group('money reads as people say it', () {
    // Prices are stored in piastres and shown in pounds, with Western numerals.
    test('a whole number of pounds drops the piastres', () {
      expect(s.price(15000), '150 ج');
    });

    test('piastres are shown when there are any', () {
      expect(s.price(15050), '150.50 ج');
    });

    test('free is a word, not a zero', () {
      expect(s.price(0), 'مجاناً');
    });
  });
}
