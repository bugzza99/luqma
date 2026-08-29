import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { freshDatabase } from './harness.mjs';

/**
 * What the platform takes from one order.
 *
 * `order_revenue_take` is the mirror of `Revenue.takeFrom` in
 * `packages/luqma_core/lib/src/models/revenue.dart`, and the two exist separately on
 * purpose: the phone *shows* the figure and the server *decides* it. Every number below
 * is asserted against the Dart side too, so a disagreement fails a test rather than
 * turning up in somebody's till.
 *
 * Here rather than in the stack suite because this is arithmetic, not a boundary: no
 * policy, no token, no trigger. It is the part that can be argued with directly.
 */
describe('what the platform takes from one order', () => {
  let db;

  before(async () => { db = await freshDatabase(); });
  after(async () => { await db.close(); });

  const take = async (revenue, basis) => Number(
    (await db.query('select public.order_revenue_take($1::jsonb, $2) as t',
                    [JSON.stringify(revenue), basis])).rows[0].t,
  );

  // The shared table. Every case here is asserted by `revenue_test.dart` too, against
  // the Dart engine — which is what makes "the phone shows it and the server decides it"
  // a guarantee rather than a hope. Before this, each side was tested against its own
  // figures, which proves each self-consistent and nothing about them agreeing.
  describe('the same numbers the phone shows', () => {
    const { cases } = JSON.parse(
      readFileSync(new URL('../../../data/revenue-cases.json', import.meta.url), 'utf8'));

    for (const c of cases) {
      it(c.why, async () => {
        assert.equal(await take({ model: c.model, value: c.value }, c.basis), c.take);
      });
    }
  });

  describe('subscription', () => {
    // The whole point of subscription-first: the money lands in the merchant's hand and
    // nothing about a single order is negotiable afterwards.
    it('takes nothing, whatever the order was worth', async () => {
      assert.equal(await take({ model: 'subscription', value: 0 }, 500000), 0);
      assert.equal(await take({ model: 'subscription', value: 9999 }, 500000), 0);
    });
  });

  describe('commission', () => {
    it('is basis points of the food', async () => {
      // 10% of 200 EGP.
      assert.equal(await take({ model: 'commission', value: 1000 }, 20000), 2000);
    });

    // Rounded down, always. Taking one piastre more than the stated rate is the sort of
    // thing that gets argued about in a shop, and it can only ever be argued downwards.
    it('rounds down rather than to nearest', async () => {
      // 12.34% of 99.99 EGP = 1233.8766 piastres.
      assert.equal(await take({ model: 'commission', value: 1234 }, 9999), 1233);
    });

    it('a rate somebody mistyped cannot exceed the order', async () => {
      // 200% is a typo for 2.00%, and it must not turn into a merchant owing double.
      assert.equal(await take({ model: 'commission', value: 20000 }, 15000), 15000);
    });

    it('a negative rate takes nothing rather than paying the merchant', async () => {
      assert.equal(await take({ model: 'commission', value: -500 }, 15000), 0);
    });
  });

  describe('prepaid', () => {
    it('is the flat fee, whatever the order was worth', async () => {
      assert.equal(await take({ model: 'prepaid', value: 500 }, 20000), 500);
      assert.equal(await take({ model: 'prepaid', value: 500 }, 400000), 500);
    });

    // The merchant made a sale. A fee that puts them in the red on it is a fee that
    // stops them taking small orders at all.
    it('never exceeds an order smaller than the fee', async () => {
      assert.equal(await take({ model: 'prepaid', value: 500 }, 300), 300);
    });
  });

  describe('the edges', () => {
    it('an order worth nothing owes nothing', async () => {
      assert.equal(await take({ model: 'commission', value: 1000 }, 0), 0);
      assert.equal(await take({ model: 'prepaid', value: 500 }, 0), 0);
    });

    it('and a negative basis is not a refund', async () => {
      assert.equal(await take({ model: 'prepaid', value: 500 }, -1000), 0);
    });

    // An order written before a field existed, or a snapshot an admin has been editing.
    // A settlement is not the place to discover a missing key by dividing by null.
    it('a snapshot missing its value takes nothing', async () => {
      assert.equal(await take({ model: 'commission' }, 20000), 0);
      assert.equal(await take({ model: 'prepaid' }, 20000), 0);
    });

    it('a snapshot naming a model that does not exist takes nothing', async () => {
      assert.equal(await take({ model: 'barter', value: 9999 }, 20000), 0);
      assert.equal(await take({}, 20000), 0);
    });
  });
});
