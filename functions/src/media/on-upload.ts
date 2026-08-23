import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onObjectFinalized } from 'firebase-functions/v2/storage';
import { logger } from 'firebase-functions';
import sharp from 'sharp';

import { MediaKind, planMediaProcessing, type MediaOutput } from './plan.js';

const REGION = 'europe-west3';

/** `uploads/{kind}/{uid}/{fileName}` — the only path this trigger acts on. */
function parseUploadPath(path: string): { kind: MediaKind; uid: string } | null {
  const parts = path.split('/');
  if (parts.length !== 4 || parts[0] !== 'uploads') return null;
  const kind = parts[1] as MediaKind;
  if (!Object.values(MediaKind).includes(kind)) return null;
  return { kind, uid: parts[2]! };
}

/**
 * Turns an uploaded original into the WebP derivatives the apps actually load, and
 * records it as a pending `media` document.
 *
 * There is no other way for an image to enter the product. That is the point: the
 * moderation gate that protects how the storefront looks only works if it has one door,
 * and this is it. Nothing here can produce an approved image.
 */
export const onMediaUploaded = onObjectFinalized(
  { region: REGION, memory: '1GiB', timeoutSeconds: 120 },
  async (event) => {
    const path = event.data.name;
    const upload = parseUploadPath(path);
    if (!upload) return; // not ours — derivatives land elsewhere and must not re-trigger

    const bucket = getStorage().bucket(event.data.bucket);
    const file = bucket.file(path);
    const [buffer] = await file.download();

    const meta = await sharp(buffer).metadata();
    const plan = planMediaProcessing({
      contentType: event.data.contentType ?? '',
      bytes: Number(event.data.size ?? buffer.length),
      width: meta.width ?? 0,
      height: meta.height ?? 0,
      kind: upload.kind,
    });

    if (!plan.accepted) {
      // Delete rather than keep: a refused original is bytes nobody will ever look at,
      // and leaving it invites a later job to find it and process it anyway.
      logger.info('upload refused', { path, reason: plan.reason });
      await file.delete({ ignoreNotFound: true });
      await getFirestore().collection('mediaRejections').add({
        path,
        uploadedBy: upload.uid,
        kind: upload.kind,
        reason: plan.reason,
        at: FieldValue.serverTimestamp(),
      });
      return;
    }

    const mediaId = getFirestore().collection('media').doc().id;
    const urls: Record<string, string> = {};
    let width = meta.width ?? 0;
    let height = meta.height ?? 0;

    for (const output of plan.outputs) {
      const { buffer: rendered, info } = await render(buffer, output);
      const target = bucket.file(`media/${mediaId}/${output.name}.webp`);
      await target.save(rendered, {
        contentType: 'image/webp',
        // A derivative never changes once written, so it can be cached hard. This is
        // most of why images feel instant on a second visit over patchy mobile data.
        metadata: { cacheControl: 'public, max-age=31536000, immutable' },
      });
      urls[output.name] = target.publicUrl();
      if (output.name === 'full') {
        width = info.width;
        height = info.height;
      }
    }

    await getFirestore().collection('media').doc(mediaId).set({
      kind: upload.kind,
      uploadedBy: upload.uid,
      url: urls.full,
      thumbUrl: urls.thumb,
      width,
      height,
      bytes: buffer.length,
      status: plan.status, // 'pending' — the only status this function can write
      createdAt: FieldValue.serverTimestamp(),
    });

    await file.delete({ ignoreNotFound: true });
    logger.info('media processed', { mediaId, kind: upload.kind });
  },
);

async function render(source: Buffer, output: MediaOutput) {
  const result = await sharp(source)
    .rotate() // honour the phone's EXIF orientation before it is stripped below
    .resize({ width: output.maxEdge, height: output.maxEdge, fit: 'inside', withoutEnlargement: true })
    .webp({ quality: output.quality })
    .toBuffer({ resolveWithObject: true });
  return { buffer: result.data, info: result.info };
}
