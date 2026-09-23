import 'package:customer_app/src/home/sections/merchant_list_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// B12. «الأعلى تقييماً» ranked one five-star rating above two hundred averaging 4.8 —
/// on a number the shop's own page will not even show under the threshold.
void main() {
  Merchant shop(String id, double avg, int count) => Merchant(
        id: id,
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: id,
        zoneId: 'z1',
        phone: '0100',
        status: MerchantStatus.approved,
        ratingAvg: avg,
        ratingCount: count,
      );

  test('a shop rated by enough people outranks one rated once', () {
    final ranked = MerchantListSection.rankByRating(
      [shop('once', 5.0, 1), shop('many', 4.8, 200)],
      minRatings: 10,
    );
    expect(ranked.map((m) => m.id), ['many', 'once']);
  });

  test('among the well-rated, the average decides', () {
    final ranked = MerchantListSection.rankByRating(
      [shop('b', 4.2, 50), shop('a', 4.9, 12), shop('c', 4.5, 300)],
      minRatings: 10,
    );
    expect(ranked.map((m) => m.id), ['a', 'c', 'b']);
  });

  test('among the few-rated, more ratings first', () {
    final ranked = MerchantListSection.rankByRating(
      [shop('x', 5.0, 2), shop('y', 3.0, 7), shop('z', 0, 0)],
      minRatings: 10,
    );
    expect(ranked.map((m) => m.id), ['y', 'x', 'z']);
  });
}
