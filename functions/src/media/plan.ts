/**
 * What to do with an uploaded image, decided before anything is written.
 *
 * Kept as a pure function so the rules that actually matter — what is allowed in, what
 * shape it has to be, what it is turned into — can be tested without a bucket, a
 * Firestore, or an image library. The trigger in `on-upload.ts` does the I/O and nothing
 * else.
 */

export enum MediaKind {
  merchantLogo = 'merchantLogo',
  merchantCover = 'merchantCover',
  menuItem = 'menuItem',
  dailyMeal = 'dailyMeal',
  promotion = 'promotion',
}

export enum RejectionReason {
  unsupportedType = 'unsupportedType',
  tooLarge = 'tooLarge',
  tooSmall = 'tooSmall',
  wrongAspect = 'wrongAspect',
}

export interface MediaOutput {
  name: 'full' | 'thumb';
  /** Longest edge in pixels. Never larger than the source: upscaling adds bytes and no detail. */
  maxEdge: number;
  format: 'webp';
  quality: number;
}

export type MediaPlan =
  | { accepted: true; status: 'pending'; outputs: MediaOutput[] }
  | { accepted: false; reason: RejectionReason };

export interface MediaCandidate {
  contentType: string;
  bytes: number;
  width: number;
  height: number;
  kind: MediaKind;
}

/** Formats a browser and `sharp` both handle. SVG is deliberately absent: it is a
 *  document that can carry script, not a photograph. */
const ALLOWED_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic']);

/** Above this, it is not a phone photo — it is someone uploading a print file. */
const MAX_BYTES = 15_000_000;

/**
 * Below this longest edge, the image visibly softens at the sizes the app draws it.
 *
 * Measured on the long edge, not the short one: a correctly proportioned 3:1 banner is
 * 1080x360, and a short-edge floor would refuse every banner that was exactly right.
 */
const MIN_LONG_EDGE = 600;

/**
 * Longest edge we keep, per use. Bandwidth is the constraint here, not storage — nobody
 * needs three thousand pixels of a plate of koshari on a phone on mobile data.
 */
const MAX_EDGE: Record<MediaKind, number> = {
  [MediaKind.merchantLogo]: 512,
  [MediaKind.merchantCover]: 1600,
  [MediaKind.menuItem]: 1440,
  [MediaKind.dailyMeal]: 1440,
  [MediaKind.promotion]: 1620,
};

/** Every promotion slot is 3:1, so the banner must be too. */
const PROMOTION_ASPECT = 3;
const ASPECT_TOLERANCE = 0.08;

export function planMediaProcessing(candidate: MediaCandidate): MediaPlan {
  const { contentType, bytes, width, height, kind } = candidate;

  if (!ALLOWED_TYPES.has(contentType)) {
    return { accepted: false, reason: RejectionReason.unsupportedType };
  }
  if (bytes > MAX_BYTES) {
    return { accepted: false, reason: RejectionReason.tooLarge };
  }
  if (Math.max(width, height) < MIN_LONG_EDGE) {
    return { accepted: false, reason: RejectionReason.tooSmall };
  }

  // A square image dropped into a 3:1 slot either letterboxes or crops the merchant's own
  // text out of the placement they paid for. Refusing it now is kinder than either, and
  // it is the rule that keeps a self-serve banner slot from wrecking the home screen.
  if (kind === MediaKind.promotion) {
    const aspect = width / height;
    if (Math.abs(aspect - PROMOTION_ASPECT) / PROMOTION_ASPECT > ASPECT_TOLERANCE) {
      return { accepted: false, reason: RejectionReason.wrongAspect };
    }
  }

  const sourceEdge = Math.max(width, height);
  const fullEdge = Math.min(MAX_EDGE[kind], sourceEdge);

  return {
    accepted: true,
    // No upload of any kind, from any account, arrives approved. The moderation gate has
    // exactly one door and this is it.
    status: 'pending',
    outputs: [
      { name: 'full', maxEdge: fullEdge, format: 'webp', quality: 82 },
      { name: 'thumb', maxEdge: Math.min(320, sourceEdge), format: 'webp', quality: 75 },
    ],
  };
}
