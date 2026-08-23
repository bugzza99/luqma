import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// What the platform earns from one order.
///
/// A pure computation over a snapshot frozen at order time, so changing a merchant's
/// terms in AdminApp affects future orders only and never rewrites past accounting. The
/// same arithmetic runs in the Cloud Function that applies it; this is the definition.
void main() {
  Merchant merchant({
    RevenueModel model = RevenueModel.subscription,
    int value = 0,
    int wallet = 0,
  }) =>
      Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'مطعم',
        zoneId: 'z1',
        phone: '0100',
        status: MerchantStatus.approved,
        revenueModel: model,
        revenueValue: value,
        walletBalance: wallet,
      );

  group('the snapshot', () {
    // Frozen at order time. A merchant moved from subscription to commission next month
    // must not retroactively owe commission on tonight's orders.
    test('carries the terms in force when the order was placed', () {
      final snapshot = RevenueSnapshot.of(
        merchant(model: RevenueModel.commission, value: 1200),
      );

      expect(snapshot.model, RevenueModel.commission);
      expect(snapshot.value, 1200);
    });

    test('survives a round trip', () {
      final restored = RevenueSnapshot.fromJson(
        RevenueSnapshot.of(merchant(model: RevenueModel.prepaid, value: 500))
            .toJson(),
      );

      expect(restored.model, RevenueModel.prepaid);
      expect(restored.value, 500);
    });
  });

  group('a subscription', () {
    // The whole point of subscription-first: the money lands in the merchant's hand and
    // nothing about a single order is negotiable afterwards.
    test('takes nothing from an order', () {
      final snapshot = RevenueSnapshot.of(merchant());

      expect(Revenue.takeFrom(snapshot, orderTotal: 25000), 0);
    });
  });

  group('commission', () {
    test('is a share of the order, in basis points', () {
      final snapshot = RevenueSnapshot.of(
        merchant(model: RevenueModel.commission, value: 1000),
      );

      // 10% of 250 EGP.
      expect(Revenue.takeFrom(snapshot, orderTotal: 25000), 2500);
    });

    // Money is integer piastres, and the platform rounds in the merchant's favour. Taking
    // one piastre more than the stated rate is the sort of thing that ends up argued
    // about in a shop, and it can only ever be argued about downwards.
    test('rounds down, never up', () {
      final snapshot = RevenueSnapshot.of(
        merchant(model: RevenueModel.commission, value: 1234),
      );

      // 12.34% of 999 piastres is 123.27…
      expect(Revenue.takeFrom(snapshot, orderTotal: 999), 123);
    });

    test('a free order costs nothing', () {
      final snapshot = RevenueSnapshot.of(
        merchant(model: RevenueModel.commission, value: 1000),
      );

      expect(Revenue.takeFrom(snapshot, orderTotal: 0), 0);
    });

    // A rate above 100% would mean the platform takes more than the customer paid.
    test('a nonsense rate is clamped rather than trusted', () {
      final snapshot = RevenueSnapshot.of(
        merchant(model: RevenueModel.commission, value: 50000),
      );

      expect(Revenue.takeFrom(snapshot, orderTotal: 25000), 25000);
    });
  });

  group('prepaid', () {
    // `revenueValue` is the per-order fee here, not the balance — the balance is
    // `walletBalance`, and having two fields mean the same thing is how they disagree.
    test('takes a flat fee per order', () {
      final snapshot = RevenueSnapshot.of(
        merchant(model: RevenueModel.prepaid, value: 500),
      );

      expect(Revenue.takeFrom(snapshot, orderTotal: 25000), 500);
    });

    // The fee is what it costs to carry an order; an order worth less than the fee is
    // still an order. Taking more than the total would put the merchant in the red on a
    // sale they made.
    test('never takes more than the order was worth', () {
      final snapshot = RevenueSnapshot.of(
        merchant(model: RevenueModel.prepaid, value: 500),
      );

      expect(Revenue.takeFrom(snapshot, orderTotal: 300), 300);
    });
  });

  group('whether a prepaid merchant can still take orders', () {
    test('a wallet with credit can', () {
      expect(
        Revenue.canAffordAnOrder(
          merchant(model: RevenueModel.prepaid, value: 500, wallet: 2000),
        ),
        isTrue,
      );
    });

    // The point of prepaid: the platform stops carrying a merchant who has run out,
    // rather than accumulating a debt nobody will settle.
    test('an empty wallet cannot', () {
      expect(
        Revenue.canAffordAnOrder(
          merchant(model: RevenueModel.prepaid, value: 500, wallet: 0),
        ),
        isFalse,
      );
    });

    // Stopping only once it is negative means one order goes out unpaid for.
    test('a wallet too thin for one more order cannot', () {
      expect(
        Revenue.canAffordAnOrder(
          merchant(model: RevenueModel.prepaid, value: 500, wallet: 300),
        ),
        isFalse,
      );
    });

    test('a subscriber is never stopped by a wallet they do not use', () {
      expect(Revenue.canAffordAnOrder(merchant(wallet: 0)), isTrue);
    });

    test('a commission merchant is not either', () {
      expect(
        Revenue.canAffordAnOrder(
          merchant(model: RevenueModel.commission, value: 1000, wallet: 0),
        ),
        isTrue,
      );
    });
  });

  group('a merchant who has run out', () {
    final open = [
      for (var d = 1; d <= 7; d++)
        OpeningWindow(weekday: d, openMinute: 0, closeMinute: 1440),
    ];
    final now = DateTime(2026, 8, 23, 12);

    // The one place this reaches a customer: a merchant with an empty prepaid wallet
    // stops appearing as open, exactly like one outside its hours.
    test('stops taking orders', () {
      final broke = merchant(
        model: RevenueModel.prepaid,
        value: 500,
        wallet: 0,
      ).copyWith(openingHours: open);

      expect(broke.acceptsOrdersAt(now), isFalse);
    });

    test('and starts again once the wallet is topped up', () {
      final funded = merchant(
        model: RevenueModel.prepaid,
        value: 500,
        wallet: 5000,
      ).copyWith(openingHours: open);

      expect(funded.acceptsOrdersAt(now), isTrue);
    });

    test('a subscriber with no wallet is unaffected', () {
      final subscriber = merchant().copyWith(openingHours: open);

      expect(subscriber.acceptsOrdersAt(now), isTrue);
    });
  });
}
