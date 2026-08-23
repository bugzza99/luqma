import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  RevenueModel,
  applyRevenue,
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
    const effect = applyRevenue(snapshot(RevenueModel.subscription), 25000);

    assert.equal(effect.amount, 0);
    assert.equal(effect.walletDelta, 0);
    assert.equal(effect.commissionDelta, 0);
  });

  // Accrued, not collected. The money is in the merchant's hand; this is a running
  // total of what they owe, settled in cash later.
  it('commission accrues against the merchant', () => {
    const effect = applyRevenue(snapshot(RevenueModel.commission, 1000), 25000);

    assert.equal(effect.amount, 2500);
    assert.equal(effect.commissionDelta, 2500);
    assert.equal(effect.walletDelta, 0);
  });

  // Already collected. This is what makes prepaid different: the platform is spending
  // credit that was handed over in advance rather than writing down a debt.
  it('prepaid comes out of the wallet', () => {
    const effect = applyRevenue(snapshot(RevenueModel.prepaid, 500), 25000);

    assert.equal(effect.amount, 500);
    assert.equal(effect.walletDelta, -500);
    assert.equal(effect.commissionDelta, 0);
  });

  // The snapshot carries what was actually taken, so an order is a complete record of
  // its own accounting and nothing has to be recomputed from a merchant that has since
  // changed.
  it('writes the amount back onto the snapshot', () => {
    const effect = applyRevenue(snapshot(RevenueModel.commission, 1000), 25000);

    assert.equal(effect.snapshot.amount, 2500);
    assert.equal(effect.snapshot.model, RevenueModel.commission);
    assert.equal(effect.snapshot.value, 1000);
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
