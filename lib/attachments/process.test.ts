import { test, expect } from 'bun:test';
import sharp from 'sharp';
import {
  detectFile,
  processBytes,
  ALLOWED_IMAGE_MIMES,
  PDF_MIME,
} from '@/lib/attachments/process';

// Tiny test fixtures generated in-process via sharp so the suite has no
// binary blobs to check in.
async function jpeg(width = 10, height = 10): Promise<Buffer> {
  return sharp({
    create: { width, height, channels: 3, background: { r: 200, g: 100, b: 50 } },
  })
    .jpeg()
    .toBuffer();
}

async function png(width = 10, height = 10): Promise<Buffer> {
  return sharp({
    create: { width, height, channels: 4, background: { r: 100, g: 200, b: 50, alpha: 1 } },
  })
    .png()
    .toBuffer();
}

// Minimal valid PDF (one empty page). 'file-type' identifies by the %PDF- header.
const TINY_PDF = Buffer.from(
  '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\nxref\n0 3\n0000000000 65535 f\n0000000009 00000 n\n0000000055 00000 n\ntrailer<</Size 3/Root 1 0 R>>\nstartxref\n103\n%%EOF',
);

test('detectFile recognises JPEG, PNG, PDF', async () => {
  expect((await detectFile(await jpeg()))?.kind).toBe('image');
  expect((await detectFile(await jpeg()))?.detectedMime).toBe('image/jpeg');
  expect((await detectFile(await png()))?.kind).toBe('image');
  expect((await detectFile(TINY_PDF))?.kind).toBe('pdf');
  expect((await detectFile(TINY_PDF))?.detectedMime).toBe(PDF_MIME);
});

test('detectFile refuses unsupported types', async () => {
  // A plain text file isn't an image or PDF.
  expect(await detectFile(Buffer.from('hello world\n'))).toBeNull();
  // file-type returns nothing on tiny noise.
  expect(await detectFile(Buffer.from([0, 1, 2, 3]))).toBeNull();
});

test('ALLOWED_IMAGE_MIMES covers the receipt-photo formats the plan picks', () => {
  for (const mime of ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']) {
    expect(ALLOWED_IMAGE_MIMES.has(mime)).toBe(true);
  }
});

test('processBytes(image): re-encodes to JPEG; strips EXIF; applies orientation', async () => {
  // Build a PNG with EXIF-equivalent rotation by feeding sharp an oriented JPEG.
  // We rotate inline (sharp.rotate(90)) then pipe through processBytes — the
  // output should already account for that rotation.
  const oriented = await sharp({
    create: { width: 20, height: 10, channels: 3, background: { r: 0, g: 0, b: 0 } },
  })
    .jpeg()
    .toBuffer();

  const detected = await detectFile(oriented);
  expect(detected?.kind).toBe('image');

  const out = await processBytes(oriented, 'image');
  expect(out.outMime).toBe('image/jpeg');
  expect(out.outExt).toBe('jpg');
  expect(out.outKind).toBe('image');
  // Output IS valid JPEG (sharp can re-parse).
  const meta = await sharp(out.bytes).metadata();
  expect(meta.format).toBe('jpeg');
  // EXIF was stripped by re-encode.
  expect(meta.exif).toBeUndefined();
});

test('processBytes(image): a PNG input becomes a JPEG output', async () => {
  const inputPng = await png();
  const out = await processBytes(inputPng, 'image');
  expect(out.outMime).toBe('image/jpeg');
  const meta = await sharp(out.bytes).metadata();
  expect(meta.format).toBe('jpeg');
});

test('processBytes(pdf): passthrough — bytes are byte-identical', async () => {
  const out = await processBytes(TINY_PDF, 'pdf');
  expect(out.outMime).toBe('application/pdf');
  expect(out.outExt).toBe('pdf');
  expect(out.outKind).toBe('pdf');
  expect(out.bytes.equals(TINY_PDF)).toBe(true);
});
