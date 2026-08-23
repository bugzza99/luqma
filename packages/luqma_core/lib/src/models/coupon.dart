import 'package:freezed_annotation/freezed_annotation.dart';

import '../util/arabic_digits.dart';
import 'converters.dart';

part 'coupon.freezed.dart';
part 'coupon.g.dart';

enum CouponType {
  /// [Coupon.value] is basis points: 1500 is 15%. Applies to the food only.
  percentage,

  /// [Coupon.value] is piastres off the food.
  fixedAmount,

  /// Clears the delivery fee. The cheapest offer a merchant can make and the one that
  /// moves the most orders, because the fee is what people hesitate over.
  freeDelivery,
}

/// Who actually pays for the discount.
///
/// This matters here more than it would elsewhere: the money is collected in cash at the
/// door, so a discount is simply less cash reaching the merchant. A platform campaign is
/// therefore a debt the moment the order is placed — recorded per order rather than
/// reconstructed at the end of the month.
enum CouponFunder { merchant, platform }

enum CouponRejection {
  notFound,
  inactive,
  notYetValid,
  expired,
  minOrderNotMet,
  wrongMerchant,
  firstOrderOnly,
  alreadyUsed,
  exhausted,

  /// The coupon itself is unusable — currently only an uncapped percentage.
  malformed,
}

/// The outcome of applying a coupon to one specific basket.
sealed class CouponEvaluation {
  const CouponEvaluation();
}

final class CouponAccepted extends CouponEvaluation {
  const CouponAccepted({
    required this.subtotalDiscount,
    required this.deliveryDiscount,
    required this.platformOwesMerchant,
  });

  /// Piastres off the food.
  final int subtotalDiscount;

  /// Piastres off the delivery fee.
  final int deliveryDiscount;

  /// What Luqma owes this merchant for honouring the discount. Zero when the merchant
  /// funded it themselves.
  final int platformOwesMerchant;

  int get total => subtotalDiscount + deliveryDiscount;
}

final class CouponRejected extends CouponEvaluation {
  const CouponRejected(this.reason);

  final CouponRejection reason;
}

@freezed
abstract class Coupon with _$Coupon {
  const factory Coupon({
    required String id,

    /// Stored already normalised. Compare with [normalizeCode], never raw.
    required String code,
    required String cityId,
    required CouponType type,

    /// Basis points for [CouponType.percentage], piastres for
    /// [CouponType.fixedAmount], ignored for [CouponType.freeDelivery].
    required int value,

    /// Ceiling on a percentage discount, in piastres. Required for a percentage: an
    /// uncapped one is a merchant signing a blank cheque against an order size nobody
    /// predicted.
    int? maxDiscount,
    @Default(0) int minOrder,

    /// Restricts the coupon to one merchant. Null means it works anywhere in the city.
    String? merchantId,
    @Default(false) bool firstOrderOnly,

    /// Times one customer may use it. Zero means no limit.
    @Default(0) int perUserLimit,

    /// Times it may be used in total. Zero means no limit.
    @Default(0) int totalLimit,
    @Default(0) int usedCount,
    @Default(true) bool isActive,
    @TimestampConverter() DateTime? validFrom,
    @TimestampConverter() DateTime? validUntil,
    @Default(CouponFunder.merchant) CouponFunder fundedBy,
    String? createdByUid,
  }) = _Coupon;

  const Coupon._();

  factory Coupon.fromJson(Map<String, dynamic> json) => _$CouponFromJson(json);

  /// Folds a typed code into its stored form: trimmed, upper-cased, and with
  /// Arabic-Indic digits turned into Western ones — an Arabic keyboard produces ٢٠٢٦
  /// where the coupon was created as 2026, and the customer cannot see the difference.
  static String normalizeCode(String raw) =>
      ArabicDigits.fold(raw.trim()).toUpperCase();

  /// Applies this coupon to one basket.
  ///
  /// Pure, and duplicated on the server: the phone runs it to show the customer a total
  /// before they commit, and the Cloud Function runs it again to decide what the courier
  /// actually collects. With cash, a discount computed only on the phone is a discount
  /// anyone can edit.
  CouponEvaluation evaluate({
    required int subtotal,
    required int deliveryFee,
    required String merchantId,
    required DateTime now,
    required int userRedemptions,
    required bool isFirstOrder,
  }) {
    if (type == CouponType.percentage && maxDiscount == null) {
      return const CouponRejected(CouponRejection.malformed);
    }
    if (!isActive) return const CouponRejected(CouponRejection.inactive);
    if (validFrom != null && now.isBefore(validFrom!)) {
      return const CouponRejected(CouponRejection.notYetValid);
    }
    if (validUntil != null && now.isAfter(validUntil!)) {
      return const CouponRejected(CouponRejection.expired);
    }
    if (this.merchantId != null && this.merchantId != merchantId) {
      return const CouponRejected(CouponRejection.wrongMerchant);
    }
    if (subtotal < minOrder) {
      return const CouponRejected(CouponRejection.minOrderNotMet);
    }
    if (firstOrderOnly && !isFirstOrder) {
      return const CouponRejected(CouponRejection.firstOrderOnly);
    }
    if (perUserLimit > 0 && userRedemptions >= perUserLimit) {
      return const CouponRejected(CouponRejection.alreadyUsed);
    }
    if (totalLimit > 0 && usedCount >= totalLimit) {
      return const CouponRejected(CouponRejection.exhausted);
    }

    final (subtotalDiscount, deliveryDiscount) = switch (type) {
      // Integer division truncates, which rounds in the merchant's favour by at most
      // one piastre — the direction to err in when the difference is settled in cash.
      CouponType.percentage => (
          _atMost(subtotal * value ~/ 10000, maxDiscount!, subtotal),
          0,
        ),
      CouponType.fixedAmount => (_atMost(value, subtotal, subtotal), 0),
      CouponType.freeDelivery => (0, deliveryFee),
    };

    final discount = subtotalDiscount + deliveryDiscount;
    return CouponAccepted(
      subtotalDiscount: subtotalDiscount,
      deliveryDiscount: deliveryDiscount,
      platformOwesMerchant: fundedBy == CouponFunder.platform ? discount : 0,
    );
  }

  static int _atMost(int amount, int cap, int basketCap) {
    final capped = amount < cap ? amount : cap;
    return capped < basketCap ? capped : basketCap;
  }
}
