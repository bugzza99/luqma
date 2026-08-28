import { describe, it } from 'node:test';
import { strictEqual, deepStrictEqual, ok } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * Telling the merchant an order arrived.
 *
 * The one notification the business depends on: an order lands, the merchant's phone is
 * in their pocket with the app closed, and if nothing rings then nothing happens. The
 * Android side has existed since Phase 4 — the `orders_critical` channel at max
 * importance, the looping alarm in new_order.wav — and has been waiting for a message.
 *
 * What these tests pin is the shape of the seam rather than the sending: the order writes
 * a row and something else drains it, so a slow FCM can never make an order slow, and a
 * dead handset can never quietly poison every future send.
 */
describe('the push outbox', () => {
  const OWNER = '00000000-0000-0000-0000-0000000000a1';
  const COURIER = '00000000-0000-0000-0000-0000000000a2';
  const CUSTOMER = '00000000-0000-0000-0000-0000000000a3';
  const MERCHANT = '00000000-0000-0000-0000-0000000000b1';
  const ZONE = '00000000-0000-0000-0000-000000000001';

  const db = async () => {
    const d = await freshDatabase();

    for (const uid of [OWNER, COURIER, CUSTOMER]) {
      await d.query(`insert into auth.users (id) values ($1)`, [uid]);
    }
    // ensure_user_profile already made the users rows; this only adds the tokens a
    // phone would have registered.
    await d.query(
      `update users set fcm_tokens = array['tok-owner-1','tok-owner-2'] where id = $1`,
      [OWNER],
    );

    await d.query(`insert into cities (id, name) values ('edku', 'إدكو')`);
    await d.query(
      `insert into zones (id, city_id, name, default_delivery_fee)
       values ($1, 'edku', 'وسط', 1000)`,
      [ZONE],
    );
    await d.query(
      `insert into merchants (id, city_id, type, name, zone_id, phone, status)
       values ($1, 'edku', 'restaurant', 'مطعم البحر', $2, '0100', 'approved')`,
      [MERCHANT, ZONE],
    );
    await d.query(
      `insert into staff (uid, scope, role, merchant_id)
       values ($1, 'merchant', 'owner', $2), ($3, 'merchant', 'courier', $2)`,
      [OWNER, MERCHANT, COURIER],
    );
    return d;
  };

  /** Places an order the way place_order would, minus the pricing. */
  const placeOrder = (d, { type = 'instant' } = {}) =>
    d.query(
      `insert into orders (city_id, merchant_id, customer_uid, type, status,
                           zone_id, address, items, pricing,
                           customer_phone, customer_name, merchant_name)
       values ('edku', $1, $2, $3, 'placed', $4, '{}'::jsonb, '[]'::jsonb,
               '{}'::jsonb, '0100', 'العميل', 'مطعم البحر')
       returning id`,
      [MERCHANT, CUSTOMER, type, ZONE],
    );

  it('an order puts one row in it, addressed to the owner', async () => {
    const d = await db();
    await placeOrder(d);

    const { rows } = await d.query('select uid, channel, data from push_outbox');
    strictEqual(rows.length, 1);
    strictEqual(rows[0].uid, OWNER);
    strictEqual(rows[0].channel, 'orders_critical');
    strictEqual(rows[0].data.kind, 'newOrder');
  });

  // The owner and their courier carry the same merchant_id. Only one of them decides
  // whether the shop takes the order, and only that one should be woken.
  it('and not to the courier, who cannot accept anything', async () => {
    const d = await db();
    await placeOrder(d);

    const { rows } = await d.query(
      'select 1 from push_outbox where uid = $1',
      [COURIER],
    );
    strictEqual(rows.length, 0);
  });

  // A daily meal is collected in a window on a named day and has no accept deadline.
  // Waking a cook at midnight for a meal they published themselves is the fastest way to
  // have them turn notifications off — and then they miss the ones that matter.
  it('a pre-order wakes nobody', async () => {
    const d = await db();
    await placeOrder(d, { type: 'preorder' });

    const { rows } = await d.query('select 1 from push_outbox');
    strictEqual(rows.length, 0);
  });

  describe('draining it', () => {
    it('hands over the account tokens as they stand now', async () => {
      const d = await db();
      await placeOrder(d);

      const { rows } = await d.query('select * from claim_push_batch(10)');
      strictEqual(rows.length, 1);
      deepStrictEqual(rows[0].tokens, ['tok-owner-1', 'tok-owner-2']);
      strictEqual(rows[0].title, 'أوردر جديد');
    });

    // Two drains running at once must not take the same row: sending one merchant the
    // same alarm twice, on a channel whose whole point is that it is loud, is worse than
    // it sounds.
    it('counts an attempt, so nothing is retried for ever', async () => {
      const d = await db();
      await placeOrder(d);

      await d.query('select * from claim_push_batch(10)');
      const { rows } = await d.query('select attempts from push_outbox');
      strictEqual(rows[0].attempts, 1);
    });

    it('stops offering a row that has failed five times', async () => {
      const d = await db();
      await placeOrder(d);
      await d.query('update push_outbox set attempts = 5');

      const { rows } = await d.query('select * from claim_push_batch(10)');
      strictEqual(rows.length, 0);
    });

    it('settling it marks it sent and stops offering it', async () => {
      const d = await db();
      await placeOrder(d);
      const claimed = await d.query('select * from claim_push_batch(10)');

      await d.query('select settle_push($1)', [claimed.rows[0].id]);

      const { rows } = await d.query('select * from claim_push_batch(10)');
      strictEqual(rows.length, 0);
    });

    it('a failure is recorded rather than swallowed', async () => {
      const d = await db();
      await placeOrder(d);
      const claimed = await d.query('select * from claim_push_batch(10)');

      await d.query('select settle_push($1, $2)', [claimed.rows[0].id, 'UNAVAILABLE']);

      const { rows } = await d.query('select sent_at, last_error from push_outbox');
      strictEqual(rows[0].sent_at, null);
      strictEqual(rows[0].last_error, 'UNAVAILABLE');
      ok(true);
    });
  });

  // The part that decides whether this still works in six months. A merchant signs in on
  // their own phone and the till; one of them is replaced; the old token lives for ever,
  // every send fails against it, and the logs fill with errors that read as a broken
  // integration rather than an old handset.
  describe('tokens FCM no longer recognises', () => {
    it('are taken off the account', async () => {
      const d = await db();
      await placeOrder(d);
      const claimed = await d.query('select * from claim_push_batch(10)');

      await d.query(`select settle_push($1, null, array['tok-owner-1'])`, [
        claimed.rows[0].id,
      ]);

      const { rows } = await d.query('select fcm_tokens from users where id = $1', [
        OWNER,
      ]);
      deepStrictEqual(rows[0].fcm_tokens, ['tok-owner-2']);
    });

    it('and the live ones are left alone', async () => {
      const d = await db();
      await placeOrder(d);
      const claimed = await d.query('select * from claim_push_batch(10)');

      await d.query(`select settle_push($1, null, array['nothing-like-this'])`, [
        claimed.rows[0].id,
      ]);

      const { rows } = await d.query('select fcm_tokens from users where id = $1', [
        OWNER,
      ]);
      deepStrictEqual(rows[0].fcm_tokens, ['tok-owner-1', 'tok-owner-2']);
    });
  });
});

/**
 * The orphan sweep, and the two ways it was wrong.
 *
 * It deletes rows from `media` and objects from Storage, so who may call it and which
 * object it matches are both worth being exact about. Neither was.
 */
describe('sweeping orphan media', () => {
  const db = async () => {
    const d = await freshDatabase();
    await d.query(
      `insert into storage.buckets (id, name, public) values ('media','media',true)
       on conflict (id) do nothing`,
    );
    return d;
  };

  /** An orphan: pending, old enough, and referenced by nothing. */
  const orphan = (d, name) =>
    d.query(
      `insert into media (kind, url, status, created_at)
       values ('menuItem',
               'https://x.supabase.co/storage/v1/object/public/media/' || $1,
               'pending', now() - interval '30 days')
       returning id`,
      [name],
    );

  it('takes the orphan row and its own object', async () => {
    const d = await db();
    await orphan(d, 'menuItem/abc1.jpg');
    await d.query(
      `insert into storage.objects (bucket_id, name) values ('media','menuItem/abc1.jpg')`,
    );

    await d.query('select sweep_orphan_media()');

    strictEqual((await d.query('select 1 from media')).rows.length, 0);
    strictEqual((await d.query('select 1 from storage.objects')).rows.length, 0);
  });

  // The match used to be `url LIKE '%' || name`, so a shorter name that happened to be a
  // suffix of somebody else's URL was deleted — the picture disappears from a menu while
  // the row still points at it.
  it('leaves an object whose name is merely a suffix of the orphan url', async () => {
    const d = await db();
    await orphan(d, 'menuItem/abc1.jpg');
    await d.query(
      `insert into storage.objects (bucket_id, name)
       values ('media','menuItem/abc1.jpg'), ('media','1.jpg')`,
    );

    await d.query('select sweep_orphan_media()');

    const left = await d.query('select name from storage.objects');
    deepStrictEqual(left.rows.map((r) => r.name), ['1.jpg']);
  });

  // `%` and `_` are wildcards to LIKE. Nothing writes such a name today, and nothing
  // stopped one either.
  it('treats a name containing % as a name, not a pattern', async () => {
    const d = await db();
    await orphan(d, 'menuItem/plain.jpg');
    await d.query(
      `insert into storage.objects (bucket_id, name)
       values ('media','menuItem/plain.jpg'), ('media','%')`,
    );

    await d.query('select sweep_orphan_media()');

    const left = await d.query('select name from storage.objects');
    deepStrictEqual(left.rows.map((r) => r.name), ['%']);
  });

  it('keeps a pending image something still points at', async () => {
    const d = await db();
    const { rows } = await orphan(d, 'cuisine/kept.jpg');
    await d.query(`insert into cities (id,name) values ('edku','إدكو')`);
    await d.query(
      `insert into cuisines (city_id, name, media_id) values ('edku','مشويات',$1)`,
      [rows[0].id],
    );

    await d.query('select sweep_orphan_media()');

    strictEqual((await d.query('select 1 from media')).rows.length, 1);
  });

  // security definer plus delete, with EXECUTE granted to PUBLIC by default, made the
  // nightly clean-up reachable from every phone in the city.
  it('is not callable by the API roles', async () => {
    const d = await db();
    const { rows } = await d.query(
      `select has_function_privilege('anon', 'public.sweep_orphan_media()', 'execute') as anon,
              has_function_privilege('authenticated', 'public.sweep_orphan_media()', 'execute') as auth`,
    );
    strictEqual(rows[0].anon, false);
    strictEqual(rows[0].auth, false);
  });
});
