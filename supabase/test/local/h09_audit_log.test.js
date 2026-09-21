import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { freshDatabase } from './harness.mjs';

const admin = '00000000-0000-0000-0000-0000000000ad';
const ordinaryUser = '00000000-0000-0000-0000-0000000000b0';

let db;
let cityId;
let zoneId;

before(async () => {
  db = await freshDatabase();

  await db.query('insert into auth.users (id) values ($1)', [ordinaryUser]);
  cityId = 'h09-audit-city';
  await db.query(
    "insert into cities (id, name, is_active) values ($1, 'Audit City', true)",
    [cityId],
  );
  const zone = await db.query(
    "insert into zones (city_id, name) values ($1, 'Audit Zone') returning id",
    [cityId],
  );
  zoneId = zone.rows[0].id;
});

after(() => db?.close());

async function merchant(name, status = 'pending') {
  const result = await db.query(
    `insert into merchants (city_id, type, name, zone_id, phone, status)
     values ($1, 'restaurant', $2, $3, '01000000000', $4)
     returning id`,
    [cityId, name, zoneId, status],
  );
  return result.rows[0].id;
}

async function actAs(uid, appMetadata = {}) {
  await db.exec(`
    create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb
      language sql stable as $fn$
        select '${JSON.stringify({ app_metadata: appMetadata })}'::jsonb
      $fn$;
  `);
}

async function actAsAdmin() {
  await actAs(admin, { admin: true });
}

describe('H-09 sensitive admin mutations', () => {
  it('creates a staff grant and records the real caller plus the granted identity', async () => {
    const merchantId = await merchant('Staff target');
    const target = '00000000-0000-0000-0000-0000000000b1';
    await db.query('insert into auth.users (id) values ($1)', [target]);

    await db.query(
      "select create_staff_profile($1, 'merchant', 'owner', $2)",
      [target, merchantId],
    );

    const audit = await db.query(
      "select action, actor, detail from audit_log where action = 'staff.created'",
    );
    assert.equal(audit.rows.length, 1);
    assert.equal(audit.rows[0].actor, admin);
    assert.equal(audit.rows[0].detail.old, null);
    assert.deepEqual(audit.rows[0].detail.new, {
      uid: target,
      role: 'owner',
      scope: 'merchant',
      merchantId,
    });
  });

  it('keeps every media decision instead of overwriting its history', async () => {
    const media = await db.query(
      `insert into media (kind, url, status, uploaded_by)
       values ('menuItem', 'https://example.com/audit.jpg', 'pending', $1)
       returning id`,
      [admin],
    );
    const mediaId = media.rows[0].id;

    await db.query("select admin_review_media($1, 'rejected', 'blurry')", [mediaId]);
    await db.query("select admin_review_media($1, 'approved', null)", [mediaId]);

    const audit = await db.query(
      `select actor, detail from audit_log
        where action = 'media.reviewed' and detail ->> 'mediaId' = $1`,
      [mediaId],
    );
    assert.equal(audit.rows.length, 2);
    assert.ok(audit.rows.every((row) => row.actor === admin));

    const rejection = audit.rows.find((row) => row.detail.new.status === 'rejected');
    assert.deepEqual(rejection.detail.old, {
      status: 'pending',
      reviewNote: null,
      reviewedBy: null,
    });
    assert.deepEqual(rejection.detail.new, {
      status: 'rejected',
      reviewNote: 'blurry',
      reviewedBy: admin,
    });

    const approval = audit.rows.find((row) => row.detail.new.status === 'approved');
    assert.deepEqual(approval.detail.old, {
      status: 'rejected',
      reviewNote: 'blurry',
      reviewedBy: admin,
    });
    assert.deepEqual(approval.detail.new, {
      status: 'approved',
      reviewNote: null,
      reviewedBy: admin,
    });
  });

  it('records merchant status changes and preserves the deleted row in detail', async () => {
    const merchantId = await merchant('Disposable shop');

    await db.query("select admin_set_merchant_status($1, 'approved')", [merchantId]);
    await db.query('select admin_delete_merchant($1)', [merchantId]);

    const statusAudit = await db.query(
      "select actor, detail from audit_log where action = 'merchant.status_changed' and detail ->> 'merchantId' = $1",
      [merchantId],
    );
    assert.equal(statusAudit.rows[0].actor, admin);
    assert.equal(statusAudit.rows[0].detail.old.status, 'pending');
    assert.equal(statusAudit.rows[0].detail.new.status, 'approved');

    const deleteAudit = await db.query(
      "select actor, detail from audit_log where action = 'merchant.deleted' and detail ->> 'merchantId' = $1",
      [merchantId],
    );
    assert.equal(deleteAudit.rows[0].actor, admin);
    assert.equal(deleteAudit.rows[0].detail.old.id, merchantId);
    assert.equal(deleteAudit.rows[0].detail.old.name, 'Disposable shop');
    assert.equal(deleteAudit.rows[0].detail.old.status, 'approved');
    assert.equal(deleteAudit.rows[0].detail.new, null);

    const gone = await db.query('select 1 from merchants where id = $1', [merchantId]);
    assert.equal(gone.rows.length, 0);
  });

  it('records coupon create/update/toggle and revenue-model old/new values', async () => {
    const merchantId = await merchant('Coupon shop', 'approved');

    const created = await db.query(
      `select * from create_coupon(
        ' save10 ', $1, 'percentage', 1000, 2000, 5000, $2,
        false, 1, 100, true, 'merchant', null, null
      )`,
      [cityId, merchantId],
    );
    const couponId = created.rows[0].id;

    await db.query(
      `select update_coupon(
        $1, 'SAVE15', 'percentage', 1500, 2500, 6000,
        true, 1, 50, true, 'merchant', null, null
      )`,
      [couponId],
    );
    await db.query('select set_coupon_active($1, false)', [couponId]);
    await db.query("select admin_set_revenue_model($1, 'prepaid', 2500)", [merchantId]);

    const actions = await db.query(
      `select action, actor, detail from audit_log
        where detail ->> 'couponId' = $1
        order by at, action`,
      [couponId],
    );
    assert.deepEqual(
      new Set(actions.rows.map((row) => row.action)),
      new Set(['coupon.created', 'coupon.updated', 'coupon.active_changed']),
    );
    assert.ok(actions.rows.every((row) => row.actor === admin));

    const createAudit = actions.rows.find((row) => row.action === 'coupon.created');
    assert.equal(createAudit.detail.old, null);
    assert.equal(createAudit.detail.new.code, 'SAVE10');

    const updateAudit = actions.rows.find((row) => row.action === 'coupon.updated');
    assert.equal(updateAudit.detail.old.code, 'SAVE10');
    assert.equal(updateAudit.detail.old.value, 1000);
    assert.equal(updateAudit.detail.new.code, 'SAVE15');
    assert.equal(updateAudit.detail.new.value, 1500);

    const activeAudit = actions.rows.find(
      (row) => row.action === 'coupon.active_changed',
    );
    assert.equal(activeAudit.detail.old.isActive, true);
    assert.equal(activeAudit.detail.new.isActive, false);

    const revenueAudit = await db.query(
      "select actor, detail from audit_log where action = 'merchant.revenue_model_changed' and detail ->> 'merchantId' = $1",
      [merchantId],
    );
    assert.equal(revenueAudit.rows[0].actor, admin);
    assert.deepEqual(revenueAudit.rows[0].detail.old, {
      model: 'commission',
      value: 500,
    });
    assert.deepEqual(revenueAudit.rows[0].detail.new, {
      model: 'prepaid',
      value: 2500,
    });
  });

  it('records subscription activation overrides and rejection reasons', async () => {
    const merchantId = await merchant('Subscription shop', 'approved');
    await db.query(
      "insert into plans (id, name, price_monthly, features, sort_order, is_active) values ('audit-plan', 'Audit', 30000, '{}', 0, true)",
    );

    const activate = await db.query(
      `insert into subscription_requests
        (merchant_id, plan_id, months, quoted_amount, payment_method, status, requested_by)
       values ($1, 'audit-plan', 3, 90000, 'cash', 'pending', $2)
       returning id`,
      [merchantId, ordinaryUser],
    );
    const activatedId = activate.rows[0].id;
    await db.query('select activate_subscription_request($1, 75000)', [activatedId]);

    const activated = await db.query(
      "select actor, detail from audit_log where action = 'subscription_request.activated' and detail ->> 'requestId' = $1",
      [activatedId],
    );
    assert.equal(activated.rows[0].actor, admin);
    assert.equal(activated.rows[0].detail.old.status, 'pending');
    assert.equal(activated.rows[0].detail.old.quotedAmount, 90000);
    assert.equal(activated.rows[0].detail.new.status, 'activated');
    assert.equal(activated.rows[0].detail.new.amount, 75000);

    const reject = await db.query(
      `insert into subscription_requests
        (merchant_id, plan_id, months, quoted_amount, payment_method, status, requested_by)
       values ($1, 'audit-plan', 1, 30000, 'transfer', 'pending', $2)
       returning id`,
      [merchantId, ordinaryUser],
    );
    const rejectedId = reject.rows[0].id;
    await db.query(
      "select reject_subscription_request($1, 'transfer not received')",
      [rejectedId],
    );

    const rejected = await db.query(
      "select actor, detail from audit_log where action = 'subscription_request.rejected' and detail ->> 'requestId' = $1",
      [rejectedId],
    );
    assert.equal(rejected.rows[0].actor, admin);
    assert.equal(rejected.rows[0].detail.old.status, 'pending');
    assert.equal(rejected.rows[0].detail.new.status, 'rejected');
    assert.equal(rejected.rows[0].detail.new.reason, 'transfer not received');
  });

  it('does not let a non-admin append evidence or invoke an admin mutation', async () => {
    const merchantId = await merchant('Protected shop');
    await actAs(ordinaryUser);

    await db.exec('set role authenticated');
    try {
      await assert.rejects(
        db.query(
          "insert into audit_log (action, actor) values ('forged', $1)",
          [ordinaryUser],
        ),
        /row-level security|permission denied/,
      );
      await assert.rejects(
        db.query("select admin_set_merchant_status($1, 'approved')", [merchantId]),
        /only an admin/,
      );
    } finally {
      await db.exec('reset role');
      await actAsAdmin();
    }

    const audit = await db.query(
      "select count(*)::int as n from audit_log where action = 'forged'",
    );
    assert.equal(audit.rows[0].n, 0);
  });
});
