import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { logger } from 'firebase-functions';

import { applyRevenue, planExpiry, type RevenueSnapshot, type TermRow } from './engine.js';

/**
 * The I/O half of the revenue engine. Every decision lives in `engine.ts`, which is
 * tested without a database; this reads, writes, and does nothing else.
 */

const REGION = 'europe-west3';
const FREE_PLAN = 'free';

/**
 * Applies the revenue snapshot the moment an order is delivered.
 *
 * Delivered is the only status that moves money, because it is the only one where cash
 * actually changed hands. Everything before it is a promise.
 */
export const onOrderDelivered = onDocumentUpdated(
  { region: REGION, document: 'orders/{orderId}' },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    // Only the transition, never the state. A document rewritten for any other reason —
    // a courier's name, a note — would otherwise charge the merchant a second time.
    if (before.status === 'delivered' || after.status !== 'delivered') return;

    const snapshot = after.revenue as RevenueSnapshot | undefined;
    if (!snapshot) {
      // An order placed before the snapshot existed, or one written by hand. Charging a
      // guess would be worse than charging nothing; the admin can see it in the logs.
      logger.warn('order delivered with no revenue snapshot', {
        orderId: event.params.orderId,
      });
      return;
    }

    // Already applied. A trigger can fire more than once for one write, and this one
    // spends money — so it has to be safe to run twice.
    if (snapshot.amount > 0) return;

    // Handed over whole. Which part of it the platform charges on is `engine.ts`'s
    // decision, not this file's — this one reads and writes and nothing else.
    const effect = applyRevenue(snapshot, {
      subtotal: (after.pricing?.subtotal as number | undefined) ?? 0,
      deliveryFee: (after.pricing?.deliveryFee as number | undefined) ?? 0,
    });
    if (effect.amount === 0) return;

    const db = getFirestore();
    const batch = db.batch();

    // One batch, so a failure cannot leave a wallet decremented for an order whose
    // snapshot never recorded it.
    batch.update(event.data!.after.ref, { revenue: effect.snapshot });

    const merchant = db.collection('merchants').doc(after.merchantId as string);
    if (effect.walletDelta !== 0) {
      batch.update(merchant, {
        walletBalance: FieldValue.increment(effect.walletDelta),
      });
    }
    if (effect.commissionDelta !== 0) {
      batch.update(merchant, {
        commissionOwed: FieldValue.increment(effect.commissionDelta),
      });
    }

    await batch.commit();
  },
);

/**
 * Nightly: expires subscriptions and puts those merchants back on Free.
 *
 * Expiry is a date passing rather than a flag somebody remembers to flip — this is what
 * turns that date into a change. It runs before the city wakes up, so a merchant who
 * lapsed overnight finds out before their first order rather than in the middle of one.
 */
export const dailyMaintenance = onSchedule(
  { region: REGION, schedule: '0 5 * * *', timeZone: 'Africa/Cairo' },
  async () => {
    const db = getFirestore();
    // Read whole, deliberately. Narrowing this to expired rows would be wrong rather
    // than merely bounded: whether a term counts depends on whether a *later* one
    // exists for the same merchant, and a query for expired rows cannot see the
    // renewal that makes them irrelevant. Bounding this properly means putting the
    // term's end date on the merchant document; until then, this is a few dozen rows.
    const snapshot = await db.collection('subscriptions').get();

    const terms: TermRow[] = [];
    for (const doc of snapshot.docs) {
      const data = doc.data();
      const expiresAt = data.expiresAt;
      // One unreadable row must not take the night with it. `planExpiry` refuses a bad
      // date too, but the cast below is where it used to throw, before the loop began.
      if (!(expiresAt instanceof Timestamp)) {
        logger.warn('subscription row has no usable expiry, skipped', { id: doc.id });
        continue;
      }
      terms.push({
        id: doc.id,
        merchantId: data.merchantId as string,
        planId: data.planId as string,
        expiresAt: expiresAt.toDate(),
        settled: data.settledAt != null,
      });
    }

    const plan = planExpiry(terms, new Date());
    if (plan.downgrade.length === 0) {
      logger.info('nothing expired', { warned: plan.expiringSoon.length });
      return;
    }

    const batch = db.batch();
    for (const merchantId of plan.downgrade) {
      batch.update(db.collection('merchants').doc(merchantId), {
        planId: FREE_PLAN,
        updatedAt: FieldValue.serverTimestamp(),
      });
      // Written down rather than silently applied: a merchant who loses their badge
      // overnight will ask why, and somebody has to be able to answer.
      batch.set(db.collection('auditLog').doc(), {
        action: 'subscriptionExpired',
        by: 'system',
        merchantId,
        at: FieldValue.serverTimestamp(),
      });
    }

    // The pass's memory of itself, in the same batch as the downgrade it records — so
    // it can never mark a row settled for a downgrade that did not commit.
    for (const subscriptionId of plan.settle) {
      batch.update(db.collection('subscriptions').doc(subscriptionId), {
        settledAt: FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    logger.info('subscriptions expired', {
      downgraded: plan.downgrade.length,
      warned: plan.expiringSoon.length,
    });
  },
);
