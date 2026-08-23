import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Money is in piastres throughout: 100 piastres to the pound. Percentages are basis
/// points, so 1500 is 15%. Both are integers because a discount computed in floating
/// point eventually hands a courier a figure that is one piastre off the merchant's,
/// and neither of them can prove which is right.
void main() {
  final now = DateTime(2026, 8, 20, 13, 0);

  Coupon coupon({
    CouponType type = CouponType.percentage,
    int value = 1500,
    int? maxDiscount = 3000,
    int minOrder = 0,
    String? merchantId,
    bool firstOrderOnly = false,
    int perUserLimit = 0,
    int totalLimit = 0,
    int usedCount = 0,
    bool isActive = true,
    DateTime? validFrom,
    DateTime? validUntil,
    CouponFunder fundedBy = CouponFunder.merchant,
  }) {
    return Coupon(
      id: 'c1',
      code: 'AHLAN',
      cityId: 'edku',
      type: type,
      value: value,
      maxDiscount: maxDiscount,
      minOrder: minOrder,
      merchantId: merchantId,
      firstOrderOnly: firstOrderOnly,
      perUserLimit: perUserLimit,
      totalLimit: totalLimit,
      usedCount: usedCount,
      isActive: isActive,
      validFrom: validFrom ?? DateTime(2026, 8, 1),
      validUntil: validUntil ?? DateTime(2026, 9, 1),
      fundedBy: fundedBy,
    );
  }

  CouponEvaluation check(
    Coupon c, {
    int subtotal = 10000,
    int deliveryFee = 1000,
    String merchantId = 'm1',
    int userRedemptions = 0,
    bool isFirstOrder = true,
    DateTime? at,
  }) {
    return c.evaluate(
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      merchantId: merchantId,
      userRedemptions: userRedemptions,
      isFirstOrder: isFirstOrder,
      now: at ?? now,
    );
  }

  group('what a coupon takes off', () {
    test('a percentage applies to the food, not to the delivery fee', () {
      // 15% of 100.00 EGP is 15.00 — the 10.00 delivery is untouched.
      final result = check(coupon(value: 1500), subtotal: 10000, deliveryFee: 1000);
      expect(result, isA<CouponAccepted>());
      expect((result as CouponAccepted).subtotalDiscount, 1500);
      expect(result.deliveryDiscount, 0);
    });

    // The rule that stops a large order from costing the merchant far more than they
    // ever intended to give away.
    test('a percentage is capped by its maximum discount', () {
      final result = check(
        coupon(value: 1500, maxDiscount: 3000),
        subtotal: 200000, // a 2000 EGP party order
      );
      expect((result as CouponAccepted).subtotalDiscount, 3000, reason: 'capped at 30 EGP');
    });

    test('a fixed amount comes off the food', () {
      final result = check(coupon(type: CouponType.fixedAmount, value: 2000));
      expect((result as CouponAccepted).subtotalDiscount, 2000);
    });

    test('a fixed amount larger than the order never makes the total negative', () {
      final result = check(
        coupon(type: CouponType.fixedAmount, value: 20000),
        subtotal: 5000,
      );
      expect((result as CouponAccepted).subtotalDiscount, 5000);
    });

    test('free delivery clears the fee and leaves the food alone', () {
      final result = check(
        coupon(type: CouponType.freeDelivery),
        subtotal: 10000,
        deliveryFee: 1500,
      );
      expect((result as CouponAccepted).subtotalDiscount, 0);
      expect(result.deliveryDiscount, 1500);
    });

    test('free delivery on an order that already has none discounts nothing', () {
      final result = check(coupon(type: CouponType.freeDelivery), deliveryFee: 0);
      expect((result as CouponAccepted).deliveryDiscount, 0);
    });
  });

  group('why a coupon is refused', () {
    test('an inactive coupon', () {
      expect(
        (check(coupon(isActive: false)) as CouponRejected).reason,
        CouponRejection.inactive,
      );
    });

    test('a coupon whose window has not opened yet', () {
      final result = check(coupon(validFrom: DateTime(2026, 9, 1)));
      expect((result as CouponRejected).reason, CouponRejection.notYetValid);
    });

    test('an expired coupon', () {
      final result = check(coupon(validUntil: DateTime(2026, 8, 10)));
      expect((result as CouponRejected).reason, CouponRejection.expired);
    });

    test('an order below the coupon minimum', () {
      final result = check(coupon(minOrder: 15000), subtotal: 10000);
      expect((result as CouponRejected).reason, CouponRejection.minOrderNotMet);
    });

    test('a coupon belonging to a different merchant', () {
      final result = check(coupon(merchantId: 'm2'), merchantId: 'm1');
      expect((result as CouponRejected).reason, CouponRejection.wrongMerchant);
    });

    test('a coupon with no merchant works anywhere', () {
      expect(check(coupon(merchantId: null)), isA<CouponAccepted>());
    });

    test('a first-order coupon used by a returning customer', () {
      final result = check(coupon(firstOrderOnly: true), isFirstOrder: false);
      expect((result as CouponRejected).reason, CouponRejection.firstOrderOnly);
    });

    test('a customer who has already used it as many times as allowed', () {
      final result = check(coupon(perUserLimit: 1), userRedemptions: 1);
      expect((result as CouponRejected).reason, CouponRejection.alreadyUsed);
    });

    test('a campaign that has run out of redemptions', () {
      final result = check(coupon(totalLimit: 100, usedCount: 100));
      expect((result as CouponRejected).reason, CouponRejection.exhausted);
    });

    test('a limit of zero means no limit', () {
      expect(
        check(coupon(perUserLimit: 0, totalLimit: 0, usedCount: 9999)),
        isA<CouponAccepted>(),
      );
    });
  });

  group('a percentage coupon must have a ceiling', () {
    // Not a warning — the coupon is unusable, because an uncapped percentage is a
    // merchant signing a blank cheque.
    test('a percentage with no maximum is refused rather than applied', () {
      final result = check(coupon(value: 1500, maxDiscount: null));
      expect((result as CouponRejected).reason, CouponRejection.malformed);
    });

    test('a fixed amount needs no maximum', () {
      expect(
        check(coupon(type: CouponType.fixedAmount, value: 2000, maxDiscount: null)),
        isA<CouponAccepted>(),
      );
    });

    test('free delivery needs no maximum', () {
      expect(
        check(coupon(type: CouponType.freeDelivery, maxDiscount: null)),
        isA<CouponAccepted>(),
      );
    });
  });

  group('codes as people actually type them', () {
    test('matching ignores case and stray spaces', () {
      expect(Coupon.normalizeCode('  ahlan '), 'AHLAN');
      expect(Coupon.normalizeCode('AhLaN'), 'AHLAN');
    });

    test('Arabic-Indic digits are folded to Western ones', () {
      // A phone with an Arabic keyboard produces ٢٠٢٦; the stored code has 2026.
      expect(Coupon.normalizeCode('عيد٢٠٢٦'), 'عيد2026');
    });
  });

  group('who pays', () {
    test('a merchant-funded discount owes the merchant nothing', () {
      final result = check(coupon(fundedBy: CouponFunder.merchant));
      expect((result as CouponAccepted).platformOwesMerchant, 0);
    });

    // The whole reason `fundedBy` exists: with cash on delivery the merchant hands over
    // the discount at the door, so a platform campaign is a debt from the first order,
    // not something to reconstruct from memory at the end of the month.
    test('a platform-funded discount is recorded as owed to the merchant', () {
      final result = check(coupon(fundedBy: CouponFunder.platform, value: 1500));
      expect((result as CouponAccepted).platformOwesMerchant, 1500);
    });

    test('a platform-funded free delivery is owed too', () {
      final result = check(
        coupon(type: CouponType.freeDelivery, fundedBy: CouponFunder.platform),
        deliveryFee: 1200,
      );
      expect((result as CouponAccepted).platformOwesMerchant, 1200);
    });
  });
}
