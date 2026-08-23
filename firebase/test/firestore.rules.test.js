import { after, before, beforeEach, describe, it } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, collection, getDocs } from 'firebase/firestore';

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
  env.authenticatedContext(uid, { merchantId: 'm1' }).firestore();
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
