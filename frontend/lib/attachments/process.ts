// Receipt-photo processing pipeline. RECEIPT_PHOTOS_PLAN §5.1 + §0.7.
//
// Two stages:
//   1. `detectFile`  — magic-byte type sniff (`file-type`), refuses anything
//      not in the allowlist. Defends against renamed-extension uploads (the
//      §10 "mime spoofing" risk).
//   2. `processBytes` — server-side transform of the raw bytes:
//        - images → JPEG via sharp, with EXIF read for orientation correction
//          (the rotate() call), then EXIF entirely stripped by re-encode
//          (sharp does NOT preserve metadata on output unless asked).
//          This is the HEIC→JPEG transcode the §0 decision picked (1b):
//          universal renderability for receipts taken on iPhone (HEIC) when
//          viewed on desktop Chrome / Firefox (which don't render HEIC).
//        - PDFs → passthrough (sharp doesn't decode PDFs, and they already
//          render universally).

import sharp from 'sharp';
import { fileTypeFromBuffer } from 'file-type';

/** Allowed inputs (sniffed mime, not Content-Type header). */
export const ALLOWED_IMAGE_MIMES = new Set<string>([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
]);
export const PDF_MIME = 'application/pdf';

export interface DetectedFile {
  kind: 'image' | 'pdf';
  /** Mime detected by magic bytes (may differ from the upload's Content-Type). */
  detectedMime: string;
}

/** Sniff the buffer's true type. Returns null when the type isn't supported. */
export async function detectFile(buf: Buffer): Promise<DetectedFile | null> {
  const sniff = await fileTypeFromBuffer(buf);
  if (!sniff) return null;
  if (sniff.mime === PDF_MIME) return { kind: 'pdf', detectedMime: PDF_MIME };
  if (ALLOWED_IMAGE_MIMES.has(sniff.mime)) {
    return { kind: 'image', detectedMime: sniff.mime };
  }
  return null;
}

export interface ProcessedFile {
  /** The bytes to write to disk. */
  bytes: Buffer;
  /** Mime to store in the DB + serve with. */
  outMime: 'image/jpeg' | 'application/pdf';
  /** File extension for the on-disk filename. */
  outExt: 'jpg' | 'pdf';
  /** Kind for `transaction_attachments.kind`. */
  outKind: 'image' | 'pdf';
}

/** Transform raw bytes into the canonical stored shape. Images are
 *  re-encoded to JPEG (HEIC included), with orientation applied and EXIF
 *  stripped; PDFs are written as-is. */
export async function processBytes(rawBuf: Buffer, kind: 'image' | 'pdf'): Promise<ProcessedFile> {
  if (kind === 'pdf') {
    return { bytes: rawBuf, outMime: 'application/pdf', outExt: 'pdf', outKind: 'pdf' };
  }
  const bytes = await sharp(rawBuf, { failOn: 'truncated' })
    .rotate()                  // apply EXIF orientation BEFORE strip
    .jpeg({ quality: 88 })     // re-encode (covers HEIC→JPEG); sharp strips
                               // EXIF by default — we don't pass withMetadata().
    .toBuffer();
  return { bytes, outMime: 'image/jpeg', outExt: 'jpg', outKind: 'image' };
}
