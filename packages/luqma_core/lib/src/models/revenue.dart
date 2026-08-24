import 'merchant.dart';
import 'order.dart';

/// What the platform earns from one order.
///
/// A pure module rather than a collection, driven entirely by the snapshot frozen onto
/// the order at the moment it was placed. That is what makes the revenue model safely
/// switchable at runtime: moving a merchant from subscription to commission next month
/// changes future orders and never rewrites what was already agreed.
///
/// The same arithmetic runs in the Cloud Function that applies it. This is the
/// definition; the function is the application.
abstract final class Revenue {
  const Revenue._();

  /// One hundred per cent, in basis points.
  static const _wholeOrder = 10000;

  /// What the platform's cut is charged on: **the food, never the bill.**
  ///
  /// The delivery fee is not the platform's to take a share of. When the platform does
  /// the delivering the fee is already the platform's and the merchant never sees it, so
  /// charging a percentage of it as well is charging a merchant for money they did not
  /// receive — and there is no answer to a merchant who asks why. When the merchant
  /// delivers, the fee is fuel and a driver rather than a margin.
  ///
  /// The mirror of `commissionBasis` in `functions/src/revenue/engine.ts`, and pinned to
  /// the same figures by the tests on both sides.
  static int basisFor(OrderPricing pricing) => pricing.subtotal;

  /// What the platform takes from a sale worth [basis] piastres.
  ///
  /// Never more than the order was worth. Under commission that is a clamp on a rate
  /// somebody mistyped; under prepaid it is the honest answer for an order smaller than
  /// the flat fee — the merchant made a sale, and a fee that puts them in the red on it
  /// is a fee that stops them accepting small orders at all.
  static int takeFrom(RevenueSnapshot snapshot, {required int basis}) {
    if (basis <= 0) return 0;

    final take = switch (snapshot.model) {
      // The whole point of subscription-first: the money lands in the merchant's hand
      // and nothing about a single order is negotiable afterwards.
      RevenueModel.subscription => 0,
      // Rounded down, always. Taking one piastre more than the stated rate is the sort
      // of thing that gets argued about in a shop, and it can only be argued downwards.
      RevenueModel.commission => (basis * snapshot.value) ~/ _wholeOrder,
      // A flat fee per order, taken out of the wallet. `value` is the fee, not the
      // balance — the balance is `Merchant.walletBalance`, and two fields meaning the
      // same thing is how they come to disagree.
      RevenueModel.prepaid => snapshot.value,
    };

    if (take < 0) return 0;
    return take > basis ? basis : take;
  }

  /// Whether [merchant] can carry one more order.
  ///
  /// Only prepaid can answer no. It is the point of prepaid: the platform stops carrying
  /// a merchant who has run out, rather than accruing a debt nobody will settle. The
  /// check is made *before* the order rather than after, because stopping once the
  /// balance is already negative means one order went out unpaid for.
  static bool canAffordAnOrder(Merchant merchant) {
    if (merchant.revenueModel != RevenueModel.prepaid) return true;
    return merchant.walletBalance >= merchant.revenueValue;
  }
}
