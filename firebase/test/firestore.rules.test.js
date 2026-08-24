import { after, before, beforeEach, describe, it } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  getDocs,
  query,
  where,
} from 'firebase/firestore';

// The rules are the only thing standing between a customer's phone and everyone else's
// data. Everything below is a rule someone would otherwise have to remember.

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'luqma-edku',
    firestore: {
      rules: readFileSync('firebase/firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const customer = (uid = 'cust1') => env.authenticatedContext(uid).firestore();
const merchantOwner = (uid = 'owner1') =>
  env
    .authenticatedContext(uid, { merchantId: 'm1', role: 'owner', scope: 'merchant' })
    .firestore();
const admin = () => env.authenticatedContext('admin1', { admin: true }).firestore();
const anonymous = () => env.unauthenticatedContext().firestore();

/** Writes fixture data with the rules switched off. */
const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));

describe('merchants', () => {
  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'merchants/m1'), {
        cityId: 'edku',
        status: 'approved',
        name: 'مطعم',
        ownerUid: 'owner1',
        deliveryFeeOverride: 1000,
        planId: 'free',
        revenueModel: 'subscription',
      });
      await setDoc(doc(db, 'merchants/m2'), { cityId: 'edku', status: 'pending' });
      await setDoc(doc(db, 'merchants/pending1'), {
        cityId: 'edku',
        status: 'pending',
        ownerUid: 'owner2',
      });
    }));

  it('anyone may read an approved merchant, signed in or not', async () => {
    await assertSucceeds(getDoc(doc(anonymous(), 'merchants/m1')));
  });

  it('a pending merchant is not public', async () => {
    await assertFails(getDoc(doc(customer(), 'merchants/m2')));
  });

  it('a customer cannot edit a merchant', async () => {
    await assertFails(updateDoc(doc(customer(), 'merchants/m1'), { name: 'مخترق' }));
  });

  it('an owner may edit their own presentation fields', async () => {
    await assertSucceeds(
      updateDoc(doc(merchantOwner(), 'merchants/m1'), { name: 'الاسم الجديد' }),
    );
  });

  // The fields that decide what the platform earns are not the merchant's to set.
  it('an owner cannot change their own plan', async () => {
    await assertFails(updateDoc(doc(merchantOwner(), 'merchants/m1'), { planId: 'premium' }));
  });

  it('an owner cannot change their own revenue model', async () => {
    await assertFails(
      updateDoc(doc(merchantOwner(), 'merchants/m1'), { revenueModel: 'commission' }),
    );
  });

  // Written against a *pending* merchant on purpose: setting a field to the value it
  // already holds is not a change, so Firestore never consults the rule and the test
  // would pass without proving anything.
  it('an owner cannot approve themselves', async () => {
    const owner = env.authenticatedContext('owner2', { merchantId: 'pending1' }).firestore();
    await assertFails(updateDoc(doc(owner, 'merchants/pending1'), { status: 'approved' }));
  });

  it('an owner cannot invent their own rating', async () => {
    await assertFails(updateDoc(doc(merchantOwner(), 'merchants/m1'), { ratingAvg: 5 }));
  });

  // The delivery fee range is configured by the admin. Clamping it only in the app would
  // leave the actual limit to whoever is holding the phone.
  it('an owner may set a delivery fee inside the allowed range', async () => {
    await assertSucceeds(
      updateDoc(doc(merchantOwner(), 'merchants/m1'), { deliveryFeeOverride: 1500 }),
    );
  });

  it('an owner cannot set a delivery fee above the ceiling', async () => {
    await assertFails(
      updateDoc(doc(merchantOwner(), 'merchants/m1'), { deliveryFeeOverride: 99999 }),
    );
  });

  it('an owner cannot edit a merchant that is not theirs', async () => {
    await seed((db) => setDoc(doc(db, 'merchants/m3'), { status: 'approved', ownerUid: 'x' }));
    await assertFails(updateDoc(doc(merchantOwner(), 'merchants/m3'), { name: 'لا' }));
  });

  it('an admin may do what an owner may not', async () => {
    await assertSucceeds(updateDoc(doc(admin(), 'merchants/m1'), { status: 'suspended' }));
  });
});

describe('coupons', () => {
  beforeEach(() =>
    seed((db) => setDoc(doc(db, 'coupons/c1'), { code: 'AHLAN', value: 1500 })));

  // Otherwise anyone can dump every code in the city, including a merchant-specific one
  // and a campaign that has not launched. Validation goes through a callable that returns
  // the discount for one basket and never the document.
  it('a customer cannot read a coupon document', async () => {
    await assertFails(getDoc(doc(customer(), 'coupons/c1')));
  });

  it('a customer cannot list the coupons collection', async () => {
    await assertFails(getDocs(collection(customer(), 'coupons')));
  });

  it('a merchant owner cannot read coupon documents either', async () => {
    await assertFails(getDoc(doc(merchantOwner(), 'coupons/c1')));
  });

  it('an admin can', async () => {
    await assertSucceeds(getDoc(doc(admin(), 'coupons/c1')));
  });

  it('nobody but an admin may write one', async () => {
    await assertFails(setDoc(doc(customer(), 'coupons/c2'), { code: 'X' }));
    await assertSucceeds(setDoc(doc(admin(), 'coupons/c2'), { code: 'X' }));
  });
});

describe('users', () => {
  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'users/cust1'), { name: 'محمود', isBlocked: true });
      await setDoc(doc(db, 'users/cust2'), { name: 'سارة', rejectedOrdersCount: 2 });
    }));

  it('a customer reads their own document', async () => {
    await assertSucceeds(getDoc(doc(customer(), 'users/cust1')));
  });

  it('a customer cannot read someone else’s', async () => {
    await assertFails(getDoc(doc(customer(), 'users/cust2')));
  });

  // Seeded as blocked, so clearing the flag is a real change the rule has to refuse.
  it('a customer cannot unblock themselves', async () => {
    await assertFails(updateDoc(doc(customer(), 'users/cust1'), { isBlocked: false }));
  });

  it('a customer cannot reset their own refusal count', async () => {
    await assertFails(updateDoc(doc(customer(), 'users/cust1'), { rejectedOrdersCount: 0 }));
  });

  it('a customer may change their own name', async () => {
    await assertSucceeds(updateDoc(doc(customer(), 'users/cust1'), { name: 'محمود ع.' }));
  });
});

describe('media', () => {
  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'media/approved1'), { status: 'approved', url: 'a' });
      await setDoc(doc(db, 'media/pending1'), { status: 'pending', url: 'b' });
    }));

  it('an approved image is public', async () => {
    await assertSucceeds(getDoc(doc(anonymous(), 'media/approved1')));
  });

  // The moderation gate is the whole reason this collection exists; a pending image that
  // is still readable is a gate with a hole in it.
  it('a pending image is not', async () => {
    await assertFails(getDoc(doc(customer(), 'media/pending1')));
  });

  it('an uploader cannot approve their own image', async () => {
    await assertFails(updateDoc(doc(merchantOwner(), 'media/pending1'), { status: 'approved' }));
  });

  it('an admin approves images', async () => {
    await assertSucceeds(updateDoc(doc(admin(), 'media/pending1'), { status: 'approved' }));
  });
});

describe('the control plane', () => {
  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'config/appConfig'), { otpEnabled: false });
      await setDoc(doc(db, 'homeSections/s1'), { key: 'top', isVisible: true });
      await setDoc(doc(db, 'zones/z1'), { name: 'المعمورة', defaultDeliveryFee: 1000 });
    }));

  it('every phone can read the config', async () => {
    await assertSucceeds(getDoc(doc(anonymous(), 'config/appConfig')));
  });

  it('no phone can write it', async () => {
    await assertFails(updateDoc(doc(customer(), 'config/appConfig'), { otpEnabled: true }));
  });

  it('a merchant owner cannot rearrange the customer home screen', async () => {
    await assertFails(updateDoc(doc(merchantOwner(), 'homeSections/s1'), { isVisible: false }));
  });

  it('a merchant owner cannot reprice a zone', async () => {
    await assertFails(updateDoc(doc(merchantOwner(), 'zones/z1'), { defaultDeliveryFee: 0 }));
  });

  it('an admin may', async () => {
    await assertSucceeds(updateDoc(doc(admin(), 'zones/z1'), { defaultDeliveryFee: 1200 }));
  });
});

describe('the audit log', () => {
  it('an admin may append to it', async () => {
    await assertSucceeds(setDoc(doc(admin(), 'auditLog/e1'), { action: 'suspend' }));
  });

  // A log an admin can edit is a log that proves nothing.
  it('nobody may rewrite an entry, admin included', async () => {
    await seed((db) => setDoc(doc(db, 'auditLog/e1'), { action: 'suspend' }));
    await assertFails(updateDoc(doc(admin(), 'auditLog/e1'), { action: 'nothing happened' }));
  });

  it('a customer cannot read it', async () => {
    await assertFails(getDoc(doc(customer(), 'auditLog/e1')));
  });
});

describe('couriers', () => {
  // A courier who belongs to one merchant carries that merchant on their token, exactly
  // like the owner does. A platform courier carries no merchant at all.
  const merchantCourier = (uid = 'courier1') =>
    env.authenticatedContext(uid, { merchantId: 'm1', role: 'courier', scope: 'merchant' })
      .firestore();
  const platformCourier = (uid = 'courier9') =>
    env.authenticatedContext(uid, { role: 'courier', scope: 'platform' }).firestore();

  const order = (extra = {}) => ({
    cityId: 'edku',
    orderNumber: 101,
    customerUid: 'cust1',
    merchantId: 'm1',
    zoneId: 'z1',
    status: 'preparing',
    deliveryBy: 'merchant',
    pricing: { total: 13000 },
    ...extra,
  });

  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'orders/own'), order());
      await setDoc(doc(db, 'orders/platform'), order({ deliveryBy: 'platform', merchantId: 'm2' }));
      await setDoc(doc(db, 'orders/other'), order({ merchantId: 'm2' }));
      await setDoc(doc(db, 'orders/mine'), order({ merchantId: 'm2', courierUid: 'courier9' }));
    }),
  );

  it("a merchant's courier reads that merchant's orders", () =>
    assertSucceeds(getDoc(doc(merchantCourier(), 'orders/own'))));

  it("a merchant's courier cannot read another merchant's", () =>
    assertFails(getDoc(doc(merchantCourier(), 'orders/other'))));

  // Without this the platform courier cannot find the work at all: they are not assigned
  // to an order until they pick it up, and they cannot pick up what they cannot see.
  it('the platform courier reads orders the platform delivers', () =>
    assertSucceeds(getDoc(doc(platformCourier(), 'orders/platform'))));

  it("the platform courier cannot read a merchant's own deliveries", () =>
    assertFails(getDoc(doc(platformCourier(), 'orders/other'))));

  it('an order already assigned to them stays readable', () =>
    assertSucceeds(getDoc(doc(platformCourier(), 'orders/mine'))));

  it('a customer is not a courier', () =>
    assertFails(getDoc(doc(customer('cust2'), 'orders/platform'))));

  describe('taking an order out', () => {
    it('a courier may take it and put their own name on it', () =>
      assertSucceeds(
        updateDoc(doc(merchantCourier(), 'orders/own'), {
          status: 'outForDelivery',
          courierUid: 'courier1',
        }),
      ));

    // Otherwise one courier could hand another's phone a delivery, or take an order off
    // somebody who is already carrying it.
    it('a courier may not put somebody else\'s name on it', () =>
      assertFails(
        updateDoc(doc(merchantCourier(), 'orders/own'), {
          status: 'outForDelivery',
          courierUid: 'someone-else',
        }),
      ));

    it('a courier may not touch the price on the way out', () =>
      assertFails(
        updateDoc(doc(merchantCourier(), 'orders/own'), {
          status: 'outForDelivery',
          courierUid: 'courier1',
          pricing: { total: 1 },
        }),
      ));
  });

  describe('finishing', () => {
    beforeEach(() =>
      seed(async (db) => {
        await setDoc(
          doc(db, 'orders/carrying'),
          order({ status: 'outForDelivery', courierUid: 'courier1' }),
        );
      }),
    );

    it('the courier carrying it marks it delivered', () =>
      assertSucceeds(
        updateDoc(doc(merchantCourier(), 'orders/carrying'), {
          status: 'delivered',
          deliveredAt: new Date(),
        }),
      ));

    it('a courier records why a delivery failed', () =>
      assertSucceeds(
        updateDoc(doc(merchantCourier(), 'orders/carrying'), {
          status: 'cancelled',
          cancelReason: 'العميل مش موجود',
          cancelledBy: 'courier',
        }),
      ));

    // Cash: whoever marks it delivered is saying the money changed hands.
    it('another courier cannot mark it delivered', () =>
      assertFails(
        updateDoc(doc(merchantCourier('courier2'), 'orders/carrying'), {
          status: 'delivered',
        }),
      ));
  });
});

// A courier and their owner carry the same merchantId. Everything below is something a
// courier must not be able to do with it — and could, before the rules told the two
// apart by role.
describe('a courier is not an owner', () => {
  const merchantCourier = () =>
    env
      .authenticatedContext('courier1', {
        merchantId: 'm1',
        role: 'courier',
        scope: 'merchant',
      })
      .firestore();

  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'merchants/m1'), {
        cityId: 'edku',
        status: 'approved',
        name: 'مطعم',
        ownerUid: 'owner1',
      });
      await setDoc(doc(db, 'menuItems/i1'), { merchantId: 'm1', name: 'فراخ', price: 12000 });
      await setDoc(doc(db, 'orders/waiting'), {
        cityId: 'edku',
        orderNumber: 101,
        customerUid: 'cust1',
        merchantId: 'm1',
        zoneId: 'z1',
        status: 'placed',
        deliveryBy: 'merchant',
      });
    }),
  );

  it('cannot close the shop', () =>
    assertFails(updateDoc(doc(merchantCourier(), 'merchants/m1'), { pausedUntil: new Date() })));

  it('cannot change a price', () =>
    assertFails(updateDoc(doc(merchantCourier(), 'menuItems/i1'), { price: 1 })));

  // Accepting is a promise to cook something, made by whoever runs the kitchen.
  it('cannot accept an order', () =>
    assertFails(
      updateDoc(doc(merchantCourier(), 'orders/waiting'), {
        status: 'accepted',
        prepMinutes: 20,
      }),
    ));

  it('can still read the orders it will have to carry', () =>
    assertSucceeds(getDoc(doc(merchantCourier(), 'orders/waiting'))));
});

describe('daily meals', () => {
  const kitchen = () =>
    env
      .authenticatedContext('cook1', { merchantId: 'm1', role: 'owner', scope: 'merchant' })
      .firestore();

  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'dailyMeals/d1'), {
        merchantId: 'm1',
        cityId: 'edku',
        name: 'محشي',
        price: 9000,
        date: '2026-08-23',
        totalQty: 20,
        remainingQty: 8,
        status: 'published',
      });
    }),
  );

  it('anyone can read what is on offer', () =>
    assertSucceeds(getDoc(doc(anonymous(), 'dailyMeals/d1'))));

  it('the kitchen can rename its own meal', () =>
    assertSucceeds(updateDoc(doc(kitchen(), 'dailyMeals/d1'), { name: 'ورق عنب' })));

  it('the kitchen can take it down early', () =>
    assertSucceeds(updateDoc(doc(kitchen(), 'dailyMeals/d1'), { status: 'closed' })));

  // The one thing this collection exists to get right: two people tapping the last
  // portion at the same moment. A kitchen that can write the count can sell it twice.
  it('the kitchen cannot write what is left', () =>
    assertFails(updateDoc(doc(kitchen(), 'dailyMeals/d1'), { remainingQty: 99 })));

  // Raising it alone would only skew the meter — they cannot raise what is left to match.
  it('the kitchen cannot raise the total either', () =>
    assertFails(updateDoc(doc(kitchen(), 'dailyMeals/d1'), { totalQty: 99 })));

  it('another kitchen cannot touch it at all', () =>
    assertFails(
      updateDoc(
        doc(
          env
            .authenticatedContext('cook2', {
              merchantId: 'm2',
              role: 'owner',
              scope: 'merchant',
            })
            .firestore(),
          'dailyMeals/d1',
        ),
        { name: 'حاجة تانية' },
      ),
    ));
});

// ---------------------------------------------------------------------------
// Everything below was written after a pre-launch audit found the rule missing.
// Each one failed before the rule beside it existed.
// ---------------------------------------------------------------------------

describe('promotions', () => {
  const owner = (merchantId = 'm1') =>
    env
      .authenticatedContext(`owner-${merchantId}`, {
        merchantId,
        role: 'owner',
        scope: 'merchant',
      })
      .firestore();

  const promotion = (extra = {}) => ({
    cityId: 'edku',
    merchantId: 'm1',
    channel: 'homeBanner',
    status: 'approved',
    title: 'خصم',
    startAt: new Date('2026-08-01'),
    endAt: new Date('2026-09-01'),
    priority: 0,
    requestedBy: 'owner-m1',
    ...extra,
  });

  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'promotions/approved1'), promotion());
      await setDoc(doc(db, 'promotions/waiting1'), promotion({ status: 'requested' }));
    }),
  );

  // The query the customer app actually makes. Reading one document is not the test:
  // Firestore rejects a whole query it cannot prove is limited to readable documents,
  // so a rule that allows less than the query asks for returns nothing at all.
  it('a customer can run the live-promotions query the app runs', () =>
    assertSucceeds(
      getDocs(
        query(
          collection(customer(), 'promotions'),
          where('status', 'in', ['approved', 'active']),
        ),
      ),
    ));

  it('an approved promotion is readable on its own too', () =>
    assertSucceeds(getDoc(doc(customer(), 'promotions/approved1'))));

  // Approval is what makes it public. Before that it is a request nobody has answered.
  it('one still waiting for approval is not public', () =>
    assertFails(getDoc(doc(customer(), 'promotions/waiting1'))));

  it('the merchant who asked can see their own while it waits', () =>
    assertSucceeds(getDoc(doc(owner(), 'promotions/waiting1'))));

  it('a merchant may ask', () =>
    assertSucceeds(
      setDoc(doc(owner(), 'promotions/new1'), promotion({ status: 'requested' })),
    ));

  // The whole asymmetry of the feature: a merchant who could approve their own placement
  // could put unmoderated push on every phone in the city.
  it('a merchant may not approve their own', () =>
    assertFails(setDoc(doc(owner(), 'promotions/new2'), promotion({ status: 'approved' }))));

  it('a merchant may not approve one already requested', () =>
    assertFails(updateDoc(doc(owner(), 'promotions/waiting1'), { status: 'approved' })));
});

describe('moving an order through its states', () => {
  const merchantCourier = (uid = 'courier1') =>
    env
      .authenticatedContext(uid, { merchantId: 'm1', role: 'courier', scope: 'merchant' })
      .firestore();

  const order = (extra = {}) => ({
    cityId: 'edku',
    orderNumber: 101,
    customerUid: 'cust1',
    merchantId: 'm1',
    zoneId: 'z1',
    status: 'placed',
    deliveryBy: 'merchant',
    pricing: { total: 13000 },
    ...extra,
  });

  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'orders/placed1'), order());
      await setDoc(doc(db, 'orders/accepted1'), order({ status: 'accepted' }));
      await setDoc(doc(db, 'orders/preparing1'), order({ status: 'preparing' }));
      await setDoc(doc(db, 'orders/done1'), order({ status: 'delivered' }));
      await setDoc(doc(db, 'orders/gone1'), order({ status: 'cancelled' }));
    }),
  );

  describe('the merchant', () => {
    it('accepts an order that was just placed', () =>
      assertSucceeds(updateDoc(doc(merchantOwner(), 'orders/placed1'), { status: 'accepted' })));

    it('starts cooking one they accepted', () =>
      assertSucceeds(
        updateDoc(doc(merchantOwner(), 'orders/accepted1'), { status: 'preparing' }),
      ));

    it('sends out one that is cooked', () =>
      assertSucceeds(
        updateDoc(doc(merchantOwner(), 'orders/preparing1'), { status: 'outForDelivery' }),
      ));

    // The one that moves money. `onOrderDelivered` fires on this transition and spends
    // a prepaid wallet or accrues a commission — so an order must reach it through a
    // courier, not by a merchant writing the word.
    it('cannot jump a fresh order straight to delivered', () =>
      assertFails(updateDoc(doc(merchantOwner(), 'orders/placed1'), { status: 'delivered' })));

    it('cannot mark one delivered at all', () =>
      assertFails(
        updateDoc(doc(merchantOwner(), 'orders/preparing1'), { status: 'delivered' }),
      ));

    it('cannot cancel one that is already on the road', () =>
      assertFails(
        updateDoc(doc(merchantOwner(), 'orders/preparing1'), {
          status: 'cancelled',
          cancelReason: 'مش عايزين',
        }),
      ));

    // Delivered is final. An order that can be reopened is an order whose cash total can
    // be changed after the money was handed over.
    it('cannot reopen a delivered order', () =>
      assertFails(updateDoc(doc(merchantOwner(), 'orders/done1'), { status: 'preparing' })));

    it('cannot revive a cancelled one', () =>
      assertFails(updateDoc(doc(merchantOwner(), 'orders/gone1'), { status: 'accepted' })));

    // A merchant naming anyone they like as courier hands that person read and write on
    // the order, and the cash that comes with it.
    it('cannot hand the order to somebody who is not their courier', () =>
      assertFails(
        updateDoc(doc(merchantOwner(), 'orders/preparing1'), { courierUid: 'a-stranger' }),
      ));
  });

  describe('the courier', () => {
    it('takes out an order that is cooked', () =>
      assertSucceeds(
        updateDoc(doc(merchantCourier(), 'orders/preparing1'), {
          status: 'outForDelivery',
          courierUid: 'courier1',
        }),
      ));

    // Nobody has cooked it. Marking it delivered would charge the merchant for an order
    // that never left the kitchen.
    it('cannot mark a freshly placed order delivered', () =>
      assertFails(
        updateDoc(doc(merchantCourier(), 'orders/placed1'), {
          status: 'delivered',
          courierUid: 'courier1',
          deliveredAt: new Date(),
        }),
      ));

    it('cannot accept an order on behalf of the merchant', () =>
      assertFails(
        updateDoc(doc(merchantCourier(), 'orders/placed1'), { status: 'accepted' }),
      ));
  });

  describe('the customer', () => {
    it('cancels while it is still unanswered', () =>
      assertSucceeds(
        updateDoc(doc(customer(), 'orders/placed1'), {
          status: 'cancelled',
          cancelReason: 'غيرت رأيي',
        }),
      ));

    it('cannot cancel once the kitchen has started', () =>
      assertFails(
        updateDoc(doc(customer(), 'orders/preparing1'), { status: 'cancelled' }),
      ));

    it('cannot mark their own order delivered', () =>
      assertFails(updateDoc(doc(customer(), 'orders/preparing1'), { status: 'delivered' })));
  });
});

describe('menu items', () => {
  const owner = (merchantId) =>
    env
      .authenticatedContext(`owner-${merchantId}`, {
        merchantId,
        role: 'owner',
        scope: 'merchant',
      })
      .firestore();

  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'menuItems/i1'), { merchantId: 'm1', name: 'فراخ', price: 12000 });
      await setDoc(doc(db, 'menuItems/i2'), { merchantId: 'm2', name: 'كبدة', price: 9000 });
    }),
  );

  it('a merchant edits their own item', () =>
    assertSucceeds(updateDoc(doc(owner('m1'), 'menuItems/i1'), { price: 13000 })));

  // The rule read the merchantId being written rather than the one already there, so
  // rewriting it to your own turned somebody else's dish into yours.
  it('a merchant cannot claim an item belonging to another', () =>
    assertFails(updateDoc(doc(owner('m1'), 'menuItems/i2'), { merchantId: 'm1' })));

  it('a merchant cannot edit an item belonging to another', () =>
    assertFails(updateDoc(doc(owner('m1'), 'menuItems/i2'), { price: 1 })));

  it('a merchant cannot give their own item away', () =>
    assertFails(updateDoc(doc(owner('m1'), 'menuItems/i1'), { merchantId: 'm2' })));

  // On a delete there is no incoming document, so a rule written on the incoming
  // merchantId refused every merchant and let only the admin through.
  it('a merchant deletes their own item', () =>
    assertSucceeds(deleteDoc(doc(owner('m1'), 'menuItems/i1'))));

  it('a merchant cannot delete an item belonging to another', () =>
    assertFails(deleteDoc(doc(owner('m1'), 'menuItems/i2'))));
});

describe('deleting a daily meal', () => {
  const kitchen = (merchantId = 'm1') =>
    env
      .authenticatedContext(`cook-${merchantId}`, {
        merchantId,
        role: 'owner',
        scope: 'merchant',
      })
      .firestore();

  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'dailyMeals/d1'), {
        merchantId: 'm1',
        cityId: 'edku',
        name: 'محشي',
        date: '2026-08-23',
        totalQty: 20,
        remainingQty: 8,
      });
    }),
  );

  it('the kitchen deletes its own meal', () =>
    assertSucceeds(deleteDoc(doc(kitchen(), 'dailyMeals/d1'))));

  it('another kitchen cannot', () =>
    assertFails(deleteDoc(doc(kitchen('m2'), 'dailyMeals/d1'))));
});

describe('ratings', () => {
  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'orders/done1'), {
        cityId: 'edku',
        customerUid: 'cust1',
        merchantId: 'm1',
        status: 'delivered',
      });
      await setDoc(doc(db, 'orders/cooking1'), {
        cityId: 'edku',
        customerUid: 'cust1',
        merchantId: 'm1',
        status: 'preparing',
      });
    }),
  );

  const rating = (extra = {}) => ({
    orderId: 'done1',
    customerUid: 'cust1',
    merchantId: 'm1',
    stars: 5,
    ...extra,
  });

  it('a customer rates an order they received', () =>
    assertSucceeds(setDoc(doc(customer(), 'ratings/done1'), rating())));

  // Keyed by the order, so rating again corrects the first rather than adding a second.
  it('rating again corrects the first', async () => {
    await seed((db) => setDoc(doc(db, 'ratings/done1'), rating()));
    await assertSucceeds(setDoc(doc(customer(), 'ratings/done1'), rating({ stars: 3 })));
  });

  // Without this a merchant's average is anybody's to move, from anywhere, for free.
  it('cannot rate a merchant they never ordered from', () =>
    assertFails(
      setDoc(doc(customer('cust2'), 'ratings/done1'), rating({ customerUid: 'cust2' })),
    ));

  it('cannot rate an order that has not arrived', () =>
    assertFails(
      setDoc(doc(customer(), 'ratings/cooking1'), rating({ orderId: 'cooking1' })),
    ));

  // The document id is the order. A second document for the same order is a second vote.
  it('cannot file a rating under an id that is not the order', () =>
    assertFails(setDoc(doc(customer(), 'ratings/anything'), rating())));

  it('cannot rate on behalf of somebody else', () =>
    assertFails(setDoc(doc(customer('cust2'), 'ratings/done1'), rating())));
});

describe('uploading an image', () => {
  it('the uploader is recorded as the person uploading', () =>
    assertSucceeds(
      setDoc(doc(customer(), 'media/up1'), {
        status: 'pending',
        uploadedBy: 'cust1',
        path: 'uploads/up1.jpg',
      }),
    ));

  // Otherwise an upload can be filed under somebody else's name, and read by them.
  it('cannot be filed under another name', () =>
    assertFails(
      setDoc(doc(customer(), 'media/up2'), {
        status: 'pending',
        uploadedBy: 'someone-else',
        path: 'uploads/up2.jpg',
      }),
    ));
});

describe('raising an issue', () => {
  beforeEach(() =>
    seed(async (db) => {
      await setDoc(doc(db, 'orders/mine1'), {
        cityId: 'edku',
        customerUid: 'cust1',
        merchantId: 'm1',
        status: 'delivered',
      });
      await setDoc(doc(db, 'orders/theirs1'), {
        cityId: 'edku',
        customerUid: 'cust2',
        merchantId: 'm1',
        status: 'delivered',
      });
    }),
  );

  const issue = (extra = {}) => ({
    orderId: 'mine1',
    customerUid: 'cust1',
    merchantId: 'm1',
    reason: 'الأكل وصل بارد',
    status: 'open',
    ...extra,
  });

  it('a customer complains about their own order', () =>
    assertSucceeds(setDoc(doc(customer(), 'orderIssues/x1'), issue())));

  // A ticket against an order you were not part of is a complaint about a stranger's
  // dinner, filed against a merchant who has no way to answer it.
  it('cannot complain about somebody else’s order', () =>
    assertFails(setDoc(doc(customer(), 'orderIssues/x2'), issue({ orderId: 'theirs1' }))));

  it('cannot name a merchant the order was not from', () =>
    assertFails(setDoc(doc(customer(), 'orderIssues/x3'), issue({ merchantId: 'm2' }))));

  it('cannot file one in somebody else’s name', () =>
    assertFails(
      setDoc(doc(customer('cust2'), 'orderIssues/x4'), issue()),
    ));
});
