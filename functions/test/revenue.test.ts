import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  RevenueModel,
  applyRevenue,
  commissionBasis,
  planExpiry,
  takeFrom,
  type RevenueSnapshot,
} from '../src/revenue/engine.js';

const snapshot = (
  model: RevenueModel,
  value = 0,
): RevenueSnapshot => ({ model, value, amount: 0 });

/**
 * What the platform earns from one order, and what it does about it.
 *
 * The mirror of `Revenue` in `luqma_core`. Deliberately duplicated rather than shared:
 * the phone shows the figure and the server decides it, and the server's answer is the
 * one that counts. Both sides are tested against the same numbers, and a disagreement
 * between them shows up here as a failing test rather than in somebody's till.
 */
describe('what the platform takes', () => {
  it('takes nothing under a subscription', () => {
    assert.equal(takeFrom(snapshot(RevenueModel.subscription), 25000), 0);
  });

  it('takes a share under commission', () => {
    assert.equal(takeFrom(snapshot(RevenueModel.commission, 1000), 25000), 2500);
  });

  // Rounded down, always. Taking one piastre more than the stated rate is the sort of
  // thing that gets argued about in a shop, and it can only be argued downwards.
  it('rounds down, never up', () => {
    assert.equal(takeFrom(snapshot(RevenueModel.commission, 1234), 999), 123);
  });

  it('takes a flat fee under prepaid', () => {
    assert.equal(takeFrom(snapshot(RevenueModel.prepaid, 500), 25000), 500);
  });

  // A fee that puts a merchant in the red on a small sale is a fee that stops them
  // accepting small orders at all.
  it('never takes more than the order was worth', () => {
    assert.equal(takeFrom(snapshot(RevenueModel.prepaid, 500), 300), 300);
    assert.equal(takeFrom(snapshot(RevenueModel.commission, 50000), 25000), 25000);
  });

  it('takes nothing from a free order', () => {
    assert.equal(takeFrom(snapshot(RevenueModel.commission, 1000), 0), 0);
  });

  // The two sides have to agree on every one of these, or the app shows a merchant one
  // number and the ledger records another.
  it('agrees with the Dart engine on the cases it is tested against', () => {
    assert.equal(takeFrom(snapshot(RevenueModel.commission, 1000), 25000), 2500);
    assert.equal(takeFrom(snapshot(RevenueModel.commission, 1234), 999), 123);
    assert.equal(takeFrom(snapshot(RevenueModel.prepaid, 500), 300), 300);
    assert.equal(takeFrom(snapshot(RevenueModel.subscription, 0), 25000), 0);
  });
});

describe('what it does about it', () => {
  it('a subscription touches nothing', () => {
    const effect = applyRevenue(snapshot(RevenueModel.subscription), { subtotal: 25000, deliveryFee: 0 });

    assert.equal(effect.amount, 0);
    assert.equal(effect.walletDelta, 0);
    assert.equal(effect.commissionDelta, 0);
  });

  // Accrued, not collected. The money is in the merchant's hand; this is a running
  // total of what they owe, settled in cash later.
  it('commission accrues against the merchant', () => {
    const effect = applyRevenue(snapshot(RevenueModel.commission, 1000), { subtotal: 25000, deliveryFee: 0 });

    assert.equal(effect.amount, 2500);
    assert.equal(effect.commissionDelta, 2500);
    assert.equal(effect.walletDelta, 0);
  });

  // Already collected. This is what makes prepaid different: the platform is spending
  // credit that was handed over in advance rather than writing down a debt.
  it('prepaid comes out of the wallet', () => {
    const effect = applyRevenue(snapshot(RevenueModel.prepaid, 500), { subtotal: 25000, deliveryFee: 0 });

    assert.equal(effect.amount, 500);
    assert.equal(effect.walletDelta, -500);
    assert.equal(effect.commissionDelta, 0);
  });

  // The snapshot carries what was actually taken, so an order is a complete record of
  // its own accounting and nothing has to be recomputed from a merchant that has since
  // changed.
  it('writes the amount back onto the snapshot', () => {
    const effect = applyRevenue(snapshot(RevenueModel.commission, 1000), { subtotal: 25000, deliveryFee: 0 });

    assert.equal(effect.snapshot.amount, 2500);
    assert.equal(effect.snapshot.model, RevenueModel.commission);
    assert.equal(effect.snapshot.value, 1000);
  });
});

// The commission is charged on the food, not on the bill.
//
// It used to come off `pricing.total`, which carries the delivery fee. When the platform
// does the delivering that is money the merchant never sees: the courier keeps the fee,
// and the merchant was then charged a percentage of it as well. There is no answer to a
// merchant who asks why — and in a cash market the answer matters more than the piastres.
//
// The rule that replaced it fits in one sentence, which is the point:
// **commission is on the food; the delivery is not ours to take from.**
describe('what the commission is charged on', () => {
  const pricing = (subtotal: number, deliveryFee: number, extra = {}) => ({
    subtotal,
    deliveryFee,
    total: subtotal + deliveryFee,
    ...extra,
  });

  it('is the food, not the food plus the delivery', () => {
    // 100 EGP of food, 15 EGP delivery, 10%. Ten pounds, not eleven fifty.
    const effect = applyRevenue(snapshot(RevenueModel.commission, 1000),
                                pricing(10000, 1500));

    assert.equal(effect.amount, 1000);
    assert.equal(effect.commissionDelta, 1000);
  });

  it('a bigger delivery fee does not make the commission bigger', () => {
    const near = applyRevenue(snapshot(RevenueModel.commission, 1000),
                              pricing(10000, 500));
    const far = applyRevenue(snapshot(RevenueModel.commission, 1000),
                             pricing(10000, 4000));

    assert.equal(near.amount, far.amount);
  });

  // An order that is delivery and nothing else is not a sale.
  it('an order with no food is charged nothing', () => {
    const effect = applyRevenue(snapshot(RevenueModel.commission, 1000),
                                pricing(0, 1500));

    assert.equal(effect.amount, 0);
  });

  // Same rule for the flat fee: it comes out of what the merchant sold, and never
  // exceeds it. A fee that puts a merchant in the red on a small sale stops them
  // accepting small sales.
  it('the prepaid fee is capped by the food too', () => {
    const effect = applyRevenue(snapshot(RevenueModel.prepaid, 500), pricing(300, 1500));

    assert.equal(effect.amount, 300);
    assert.equal(effect.walletDelta, -300);
  });

  it('a subscription is still charged nothing at all', () => {
    const effect = applyRevenue(snapshot(RevenueModel.subscription), pricing(10000, 1500));

    assert.equal(effect.amount, 0);
  });

  // The Dart side is pinned to these same figures. A disagreement is a failing test
  // here rather than two different numbers in front of a merchant.
  it('agrees with the Dart engine on the basis', () => {
    assert.equal(commissionBasis(pricing(10000, 1500)), 10000);
    assert.equal(commissionBasis(pricing(0, 1500)), 0);
    assert.equal(commissionBasis(pricing(25000, 0)), 25000);
  });
});

describe('the daily pass over subscriptions', () => {
  const day = (iso: string) => new Date(iso);

  it('leaves a term that is still running alone', () => {
    const plan = planExpiry(
      [{ merchantId: 'm1', planId: 'basic', expiresAt: day('2026-09-01') }],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.downgrade, []);
  });

  // Expiry is a date passing. Nobody has to remember to flip anything, which is the
  // whole reason it is a date and not a flag.
  it('downgrades a term that has run out', () => {
    const plan = planExpiry(
      [{ merchantId: 'm1', planId: 'basic', expiresAt: day('2026-08-01') }],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.downgrade, ['m1']);
  });

  // The Free plan is permanent, and a merchant already on it has nothing to downgrade
  // to. Writing it again every night would be a write per merchant per day for nothing.
  it('does not downgrade a merchant already on Free', () => {
    const plan = planExpiry(
      [{ merchantId: 'm1', planId: 'free', expiresAt: day('2026-08-01') }],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.downgrade, []);
  });

  // A merchant who renewed has two terms; the latest is the one that counts. Reading
  // the older one would downgrade somebody who has just paid.
  it('reads the latest term, not the first one it finds', () => {
    const plan = planExpiry(
      [
        { merchantId: 'm1', planId: 'basic', expiresAt: day('2026-08-01') },
        { merchantId: 'm1', planId: 'basic', expiresAt: day('2026-09-15') },
      ],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.downgrade, []);
  });

  it('warns before it expires, so somebody can be asked for the money', () => {
    const plan = planExpiry(
      [{ merchantId: 'm1', planId: 'basic', expiresAt: day('2026-08-27') }],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.expiringSoon, ['m1']);
    assert.deepEqual(plan.downgrade, []);
  });

  // A term ending in a month is not news. Warning about it every night is how a warning
  // stops being read.
  it('does not warn about a term that is weeks away', () => {
    const plan = planExpiry(
      [{ merchantId: 'm1', planId: 'basic', expiresAt: day('2026-09-30') }],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.expiringSoon, []);
  });
});

// Everything below was written after a pre-launch audit. Each failed before the change
// beside it.
describe('the nightly pass, once it has already run', () => {
  const day = (iso: string) => new Date(iso);

  // The one the old guard was reaching for and missing. Downgrading writes `planId` onto
  // the *merchant*; the subscription row keeps saying `basic` for ever. So the row came
  // back every night — another write, and another `auditLog` document, per merchant per
  // night, until somebody noticed the log was unreadable.
  it('does not downgrade the same merchant a second night', () => {
    const plan = planExpiry(
      [
        {
          merchantId: 'm1',
          planId: 'basic',
          expiresAt: day('2026-08-01'),
          settled: true,
        },
      ],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.downgrade, []);
  });

  it('still downgrades one that has not been settled yet', () => {
    const plan = planExpiry(
      [{ merchantId: 'm1', planId: 'basic', expiresAt: day('2026-08-01') }],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.downgrade, ['m1']);
  });

  // A merchant who lapsed and then paid again. The settled row is history; the new term
  // is the one that counts, and it must not be dragged down by the old one.
  it('a merchant who paid again after lapsing is left alone', () => {
    const plan = planExpiry(
      [
        {
          merchantId: 'm1',
          planId: 'basic',
          expiresAt: day('2026-08-01'),
          settled: true,
        },
        { merchantId: 'm1', planId: 'basic', expiresAt: day('2026-09-30') },
      ],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.downgrade, []);
    assert.deepEqual(plan.expiringSoon, []);
  });

  // One row written by hand, or by an older version of the app, must not take the whole
  // night's billing with it. Before this, a single missing date threw inside the loop
  // and no merchant in the city was expired that night — silently.
  it('a row with no date is skipped, and the rest still run', () => {
    const plan = planExpiry(
      [
        { merchantId: 'broken', planId: 'basic', expiresAt: undefined as never },
        { merchantId: 'm2', planId: 'basic', expiresAt: day('2026-08-01') },
      ],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.downgrade, ['m2']);
  });

  it('a row with an unreadable date is skipped too', () => {
    const plan = planExpiry(
      [
        { merchantId: 'broken', planId: 'basic', expiresAt: new Date('nonsense') },
        { merchantId: 'm2', planId: 'basic', expiresAt: day('2026-08-01') },
      ],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.downgrade, ['m2']);
  });

  // A settled row is finished business: it should not raise a warning either.
  it('does not warn about a term that was already settled', () => {
    const plan = planExpiry(
      [
        {
          merchantId: 'm1',
          planId: 'basic',
          expiresAt: day('2026-08-26'),
          settled: true,
        },
      ],
      day('2026-08-24'),
    );

    assert.deepEqual(plan.expiringSoon, []);
  });
});
