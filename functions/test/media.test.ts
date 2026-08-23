import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  MediaKind,
  RejectionReason,
  planMediaProcessing,
  type MediaOutput,
  type MediaPlan,
} from '../src/media/plan.js';

/** Narrows a plan to its rejected form, failing the test if it was accepted. */
function rejection(plan: MediaPlan): RejectionReason {
  if (plan.accepted) assert.fail('expected the upload to be refused');
  return plan.reason;
}

/** Narrows a plan to its accepted form. */
function outputs(plan: MediaPlan): MediaOutput[] {
  if (!plan.accepted) assert.fail(`expected the upload to be accepted: ${plan.reason}`);
  return plan.outputs;
}

/// Photography is what makes a food app read as premium, and an unmoderated upload path
/// is how that gets lost. These are the decisions taken before a byte is written: what is
/// allowed in at all, what shape it must be, and what it is turned into.

const jpeg = { contentType: 'image/jpeg', bytes: 2_000_000 };

describe('what is allowed in', () => {
  it('accepts a normal photo', () => {
    const plan = planMediaProcessing({ ...jpeg, kind: MediaKind.menuItem, width: 1600, height: 1200 });
    assert.equal(plan.accepted, true);
  });

  it('accepts PNG and WebP', () => {
    for (const contentType of ['image/png', 'image/webp']) {
      const plan = planMediaProcessing({ contentType, bytes: 500_000, kind: MediaKind.menuItem, width: 1200, height: 900 });
      assert.equal(plan.accepted, true, contentType);
    }
  });

  // An SVG is a document that can carry script, not a photograph.
  it('refuses an SVG', () => {
    const plan = planMediaProcessing({ contentType: 'image/svg+xml', bytes: 5_000, kind: MediaKind.menuItem, width: 100, height: 100 });
    assert.equal(plan.accepted, false);
    assert.equal(rejection(plan), RejectionReason.unsupportedType);
  });

  it('refuses a file pretending to be an image', () => {
    const plan = planMediaProcessing({ contentType: 'application/pdf', bytes: 5_000, kind: MediaKind.menuItem, width: 0, height: 0 });
    assert.equal(rejection(plan), RejectionReason.unsupportedType);
  });

  it('refuses a file too large to be a phone photo', () => {
    const plan = planMediaProcessing({ ...jpeg, bytes: 30_000_000, kind: MediaKind.menuItem, width: 6000, height: 4000 });
    assert.equal(rejection(plan), RejectionReason.tooLarge);
  });

  // A 200px picture of a meal looks like a mistake at any size the app draws it.
  it('refuses an image too small to render well', () => {
    const plan = planMediaProcessing({ ...jpeg, kind: MediaKind.menuItem, width: 200, height: 150 });
    assert.equal(rejection(plan), RejectionReason.tooSmall);
  });
});

describe('promotion banners hold their shape', () => {
  it('accepts a 3:1 banner', () => {
    const plan = planMediaProcessing({ ...jpeg, kind: MediaKind.promotion, width: 1080, height: 360 });
    assert.equal(plan.accepted, true);
  });

  it('accepts a banner a hair off 3:1', () => {
    const plan = planMediaProcessing({ ...jpeg, kind: MediaKind.promotion, width: 1080, height: 368 });
    assert.equal(plan.accepted, true);
  });

  // A square banner in a 3:1 slot either letterboxes or crops the merchant's own text
  // out of their paid placement. Refusing it up front is kinder than either.
  it('refuses a square image as a banner', () => {
    const plan = planMediaProcessing({ ...jpeg, kind: MediaKind.promotion, width: 1080, height: 1080 });
    assert.equal(rejection(plan), RejectionReason.wrongAspect);
  });

  it('lets a menu photo be any shape', () => {
    const plan = planMediaProcessing({ ...jpeg, kind: MediaKind.menuItem, width: 1080, height: 1080 });
    assert.equal(plan.accepted, true);
  });
});

describe('what gets produced', () => {
  it('a full-size WebP and a thumbnail', () => {
    const plan = planMediaProcessing({ ...jpeg, kind: MediaKind.menuItem, width: 3000, height: 2000 });
    assert.equal(plan.accepted, true);
    assert.equal(outputs(plan).length, 2);
    assert.deepEqual(outputs(plan).map((o) => o.name), ['full', 'thumb']);
    assert.ok(outputs(plan).every((o) => o.format === 'webp'));
  });

  // Bandwidth in Edku is the constraint, not storage. Nobody needs 3000px of a plate of
  // koshari on a phone.
  it('caps the long edge rather than shipping the original', () => {
    const plan = planMediaProcessing({ ...jpeg, kind: MediaKind.menuItem, width: 4000, height: 3000 });
    assert.equal(outputs(plan)[0]!.maxEdge, 1440);
  });

  it('never scales a small image up', () => {
    const plan = planMediaProcessing({ ...jpeg, kind: MediaKind.menuItem, width: 900, height: 700 });
    assert.equal(outputs(plan)[0]!.maxEdge, 900);
  });

  it('a merchant logo is produced smaller than a cover', () => {
    const logo = planMediaProcessing({ ...jpeg, kind: MediaKind.merchantLogo, width: 2000, height: 2000 });
    const cover = planMediaProcessing({ ...jpeg, kind: MediaKind.merchantCover, width: 2000, height: 2000 });
    assert.ok(outputs(logo)[0]!.maxEdge < outputs(cover)[0]!.maxEdge);
  });
});

describe('the moderation gate', () => {
  // The single rule the whole premium look rests on. There is no upload path that
  // produces anything else.
  it('every accepted upload starts pending, whoever uploaded it', () => {
    for (const kind of Object.values(MediaKind)) {
      const plan = planMediaProcessing({ ...jpeg, kind, width: 1200, height: 400 });
      if (plan.accepted) assert.equal(plan.status, 'pending');
    }
  });

  it('a rejected upload is never given a status that could be approved', () => {
    const plan = planMediaProcessing({ contentType: 'image/svg+xml', bytes: 100, kind: MediaKind.menuItem, width: 10, height: 10 });
    assert.equal(plan.accepted, false);
    assert.equal('status' in plan, false);
  });
});
