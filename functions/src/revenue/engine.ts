/**
 * What the platform earns from one order, and what it does about it.
 *
 * A pure module invoked by triggers, not a collection. Everything it needs comes from
 * the snapshot frozen onto the order when it was placed, which is what makes the revenue
 * model safely switchable at run time: moving a merchant to commission next month
 * changes future orders and never rewrites what was already agreed.
 *
 * The mirror of `Revenue` in `luqma_core`. Deliberately duplicated rather than shared
 * across the language boundary — the phone shows the figure and the server decides it,
 * and the server's answer is the one that counts. Both sides are tested against the same
 * numbers, so a disagreement surfaces as a failing test rather than in somebody's till.
 */

export enum RevenueModel {
  subscription = 'subscription',
  commission = 'commission',
  prepaid = 'prepaid',
}

export interface RevenueSnapshot {
  model: RevenueModel;
  /**
   * The rate or fee in force: basis points under commission, piastres per order under
   * prepaid, meaningless under a subscription.
   */
  value: number;
  /** What was actually taken, once delivered. Zero until then. */
  amount: number;
}

/** One hundred per cent, in basis points. */
const WHOLE_ORDER = 10_000;

/**
 * What the platform takes from an order worth `orderTotal` piastres.
 *
 * Never more than the order was worth. Under commission that clamps a rate somebody
 * mistyped; under prepaid it is the honest answer for an order smaller than the flat fee
 * — the merchant made a sale, and a fee that puts them in the red on it is a fee that
 * stops them accepting small orders at all.
 */
export function takeFrom(snapshot: RevenueSnapshot, orderTotal: number): number {
  if (orderTotal <= 0) return 0;

  let take: number;
  switch (snapshot.model) {
    case RevenueModel.subscription:
      // The whole point of subscription-first: the money lands in the merchant's hand
      // and nothing about a single order is negotiable afterwards.
      take = 0;
      break;
    case RevenueModel.commission:
      // Rounded down, always. Taking one piastre more than the stated rate is the sort
      // of thing that gets argued about in a shop, and it can only be argued downwards.
      take = Math.floor((orderTotal * snapshot.value) / WHOLE_ORDER);
      break;
    case RevenueModel.prepaid:
      take = snapshot.value;
      break;
  }

  if (take < 0) return 0;
  return Math.min(take, orderTotal);
}

export interface RevenueEffect {
  /** What was taken. */
  amount: number;
  /** Change to `merchants.walletBalance`. Negative under prepaid, zero otherwise. */
  walletDelta: number;
  /** Change to the merchant's accrued commission. Zero unless on commission. */
  commissionDelta: number;
  /** The snapshot with `amount` filled in, to write back onto the order. */
  snapshot: RevenueSnapshot;
}

/**
 * Works out every change a delivered order causes. Applies nothing itself — the trigger
 * does the writing, in one batch, so a partial failure cannot leave a wallet decremented
 * for an order that was never marked delivered.
 *
 * Commission *accrues*; prepaid *spends*. That is the difference between the two: under
 * commission the money is already in the merchant's hand and this is a running total of
 * what they owe, settled in cash later. Under prepaid the credit was handed over in
 * advance and this is spending it.
 */
export function applyRevenue(
  snapshot: RevenueSnapshot,
  orderTotal: number,
): RevenueEffect {
  const amount = takeFrom(snapshot, orderTotal);

  return {
    amount,
    walletDelta: snapshot.model === RevenueModel.prepaid ? -amount : 0,
    commissionDelta: snapshot.model === RevenueModel.commission ? amount : 0,
    // Written back so an order is a complete record of its own accounting, and nothing
    // has to be recomputed later from a merchant whose terms have since changed.
    snapshot: { ...snapshot, amount },
  };
}

export interface TermRow {
  merchantId: string;
  planId: string;
  expiresAt: Date;
}

export interface ExpiryPlan {
  /** Merchants whose paid term has run out and who go back to Free. */
  downgrade: string[];
  /** Merchants whose term ends soon enough to go and ask for the money. */
  expiringSoon: string[];
}

/** How much warning is useful. Sooner is noise; later is a merchant cut off unasked. */
const WARN_WITHIN_DAYS = 5;

const FREE_PLAN = 'free';

/**
 * Decides what tonight's pass should do, from every subscription row.
 *
 * Pure, so the rule — which is entirely about dates and which term counts — is tested
 * without a database. `dailyMaintenance` does the reading and the writing.
 */
export function planExpiry(terms: TermRow[], now: Date): ExpiryPlan {
  // A merchant who renewed has more than one row, and the latest is the one that counts.
  // Reading an older one would downgrade somebody who has just paid.
  const latest = new Map<string, TermRow>();
  for (const term of terms) {
    const held = latest.get(term.merchantId);
    if (!held || term.expiresAt > held.expiresAt) latest.set(term.merchantId, term);
  }

  const downgrade: string[] = [];
  const expiringSoon: string[] = [];
  const warnBefore = new Date(now.getTime() + WARN_WITHIN_DAYS * 86_400_000);

  for (const term of latest.values()) {
    // The Free plan is permanent and there is nothing below it. Writing a downgrade
    // every night for a merchant already there would be one write per merchant per day
    // for no change at all.
    if (term.planId === FREE_PLAN) continue;

    if (term.expiresAt <= now) {
      downgrade.push(term.merchantId);
    } else if (term.expiresAt <= warnBefore) {
      expiringSoon.push(term.merchantId);
    }
  }

  return { downgrade, expiringSoon };
}
