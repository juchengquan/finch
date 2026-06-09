import { test, expect } from 'bun:test';
import { writeFile, mkdir, readFile, rm, mkdtemp } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import JSZip from 'jszip';
import {
  PACK_FORMAT_VERSION,
  PACK_DB_FILENAME,
  PACK_MANIFEST_FILENAME,
  PACK_ATTACHMENTS_PREFIX,
  buildPack,
  parsePack,
  extractPack,
  detectFileKind,
  sha256Hex,
  PackError,
} from './core/pack';

/** A stub byte stream the size of a small SQLite file. The pack module
 *  doesn't care it isn't a real SQLite header — it just hashes bytes. */
function fakeDbBytes(): Uint8Array {
  return new Uint8Array(Buffer.from('FAKE_SQLITE_BYTES_' + 'x'.repeat(200)));
}

async function tmp(): Promise<string> {
  return mkdtemp(path.join(os.tmpdir(), 'finch-pack-test-'));
}

test('buildPack: produces a zip with manifest + db + attachments; sha256s round-trip', async () => {
  const root = await tmp();
  try {
    const attDir = path.join(root, 'attachments', 'tx-a');
    await mkdir(attDir, { recursive: true });
    const jpgBytes = Buffer.from('JPEG' + 'a'.repeat(100));
    await writeFile(path.join(attDir, 'att-1.jpg'), jpgBytes);
    const pdfBytes = Buffer.from('%PDF-1.4 fake pdf');
    await writeFile(path.join(attDir, 'att-2.pdf'), pdfBytes);

    const db = fakeDbBytes();
    const { bytes, manifest } = await buildPack({
      dbBytes: db,
      attachmentFiles: [
        { id: 'att-1', relPath: 'attachments/tx-a/att-1.jpg', absPath: path.join(attDir, 'att-1.jpg') },
        { id: 'att-2', relPath: 'attachments/tx-a/att-2.pdf', absPath: path.join(attDir, 'att-2.pdf') },
      ],
      meta: {
        appVersion: '0.1.0',
        schemaVersion: '2026-06-11T00:00:00Z',
        exportedAt: '2026-06-06T12:00:00.000Z',
        exportedFrom: { device: 'web', device_id: 'host-x', device_name: 'finch-web' },
        rowCounts: { transactions: 5, accounts: 2 },
      },
    });

    expect(bytes.length).toBeGreaterThan(0);
    expect(manifest.pack_format_version).toBe(PACK_FORMAT_VERSION);
    expect(manifest.app_name).toBe('finch');
    expect(manifest.db.byte_size).toBe(db.length);
    expect(manifest.db.sha256).toBe(sha256Hex(db));
    expect(manifest.attachments.count).toBe(2);
    expect(manifest.attachments.total_bytes).toBe(jpgBytes.length + pdfBytes.length);
    // Items are sorted by rel_path for deterministic packs.
    expect(manifest.attachments.items.map((i) => i.id)).toEqual(['att-1', 'att-2']);
    expect(manifest.attachments.items[0].sha256).toBe(sha256Hex(new Uint8Array(jpgBytes)));
    expect(manifest.attachments.items[1].sha256).toBe(sha256Hex(new Uint8Array(pdfBytes)));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('parsePack + extractPack: round-trip yields identical DB + attachment bytes', async () => {
  const root = await tmp();
  try {
    const attDir = path.join(root, 'attachments', 'tx-a');
    await mkdir(attDir, { recursive: true });
    const jpg = Buffer.from('jpegPAYLOAD' + 'a'.repeat(50));
    await writeFile(path.join(attDir, 'att-1.jpg'), jpg);
    const db = fakeDbBytes();

    const { bytes } = await buildPack({
      dbBytes: db,
      attachmentFiles: [
        { id: 'att-1', relPath: 'attachments/tx-a/att-1.jpg', absPath: path.join(attDir, 'att-1.jpg') },
      ],
      meta: {
        appVersion: '0.1.0',
        schemaVersion: '2026-06-11T00:00:00Z',
        exportedAt: '2026-06-06T12:00:00.000Z',
        rowCounts: { transactions: 1 },
      },
    });

    const parsed = await parsePack(bytes);
    expect(parsed.manifest.attachments.items).toHaveLength(1);

    const dest = await mkdtemp(path.join(os.tmpdir(), 'finch-extract-'));
    try {
      const ex = await extractPack(parsed, dest);
      expect(ex.manifest.pack_format_version).toBe(PACK_FORMAT_VERSION);
      const dbOut = await readFile(ex.dbPath);
      expect(Buffer.from(dbOut).equals(Buffer.from(db))).toBe(true);
      const jpgOut = await readFile(path.join(dest, 'attachments', 'tx-a', 'att-1.jpg'));
      expect(jpgOut.equals(jpg)).toBe(true);
    } finally {
      await rm(dest, { recursive: true, force: true });
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('parsePack: rejects an unsupported pack_format_version', async () => {
  const zip = new JSZip();
  zip.file(PACK_DB_FILENAME, new Uint8Array([1, 2, 3]));
  zip.file(
    PACK_MANIFEST_FILENAME,
    JSON.stringify({
      pack_format_version: '99',
      app_name: 'finch',
      app_version: '0',
      schema_version: '0',
      exported_at: '',
      db: { filename: PACK_DB_FILENAME, byte_size: 3, sha256: sha256Hex(new Uint8Array([1, 2, 3])), row_counts: {} },
      attachments: { count: 0, total_bytes: 0, items: [] },
    }),
  );
  const bytes = await zip.generateAsync({ type: 'uint8array' });
  await expect(parsePack(bytes)).rejects.toBeInstanceOf(PackError);
  await expect(parsePack(bytes)).rejects.toThrow(/Unsupported pack format version 99/);
});

test('parsePack: rejects a manifest from another app', async () => {
  const zip = new JSZip();
  zip.file(PACK_DB_FILENAME, new Uint8Array([1, 2, 3]));
  zip.file(
    PACK_MANIFEST_FILENAME,
    JSON.stringify({
      pack_format_version: PACK_FORMAT_VERSION,
      app_name: 'evil',
      app_version: '0',
      schema_version: '0',
      exported_at: '',
      db: { filename: PACK_DB_FILENAME, byte_size: 3, sha256: sha256Hex(new Uint8Array([1, 2, 3])), row_counts: {} },
      attachments: { count: 0, total_bytes: 0, items: [] },
    }),
  );
  const bytes = await zip.generateAsync({ type: 'uint8array' });
  await expect(parsePack(bytes)).rejects.toThrow(/Not a Finch pack/);
});

test('parsePack: rejects an attachment rel_path outside attachments/', async () => {
  const zip = new JSZip();
  zip.file(PACK_DB_FILENAME, new Uint8Array([1, 2, 3]));
  const evilItem = {
    id: 'att-evil',
    rel_path: '../../etc/passwd',
    byte_size: 1,
    sha256: 'a'.repeat(64),
  };
  zip.file(
    PACK_MANIFEST_FILENAME,
    JSON.stringify({
      pack_format_version: PACK_FORMAT_VERSION,
      app_name: 'finch',
      app_version: '0',
      schema_version: '0',
      exported_at: '',
      db: { filename: PACK_DB_FILENAME, byte_size: 3, sha256: sha256Hex(new Uint8Array([1, 2, 3])), row_counts: {} },
      attachments: { count: 1, total_bytes: 1, items: [evilItem] },
    }),
  );
  const bytes = await zip.generateAsync({ type: 'uint8array' });
  await expect(parsePack(bytes)).rejects.toThrow(/Bad attachment rel_path/);
});

test('extractPack: rejects a tampered DB (sha256 mismatch)', async () => {
  // Build a valid pack, then surgically rewrite the DB entry to corrupt
  // the bytes while keeping the manifest's sha256 untouched.
  const root = await tmp();
  try {
    const db = fakeDbBytes();
    const { bytes } = await buildPack({
      dbBytes: db,
      attachmentFiles: [],
      meta: { appVersion: '0.1.0', schemaVersion: '2026-06-11T00:00:00Z', exportedAt: '', rowCounts: {} },
    });
    // Re-open, swap the DB entry's contents, re-zip.
    const zip = await JSZip.loadAsync(bytes);
    zip.file(PACK_DB_FILENAME, new Uint8Array(Buffer.from('TAMPERED' + 'x'.repeat(200))));
    const tampered = await zip.generateAsync({ type: 'uint8array' });

    const parsed = await parsePack(tampered);
    const dest = await mkdtemp(path.join(os.tmpdir(), 'finch-tamper-'));
    try {
      await expect(extractPack(parsed, dest)).rejects.toThrow(/DB sha256 mismatch/);
    } finally {
      await rm(dest, { recursive: true, force: true });
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('extractPack: rejects a tampered attachment', async () => {
  const root = await tmp();
  try {
    const attDir = path.join(root, 'attachments', 'tx-a');
    await mkdir(attDir, { recursive: true });
    const jpg = Buffer.from('jpegPAYLOAD' + 'a'.repeat(50));
    await writeFile(path.join(attDir, 'att-1.jpg'), jpg);

    const { bytes } = await buildPack({
      dbBytes: fakeDbBytes(),
      attachmentFiles: [
        { id: 'att-1', relPath: 'attachments/tx-a/att-1.jpg', absPath: path.join(attDir, 'att-1.jpg') },
      ],
      meta: { appVersion: '0.1.0', schemaVersion: '2026-06-11T00:00:00Z', exportedAt: '', rowCounts: {} },
    });
    const zip = await JSZip.loadAsync(bytes);
    zip.file('attachments/tx-a/att-1.jpg', new Uint8Array(Buffer.from('TAMPERED')));
    const tampered = await zip.generateAsync({ type: 'uint8array' });

    const parsed = await parsePack(tampered);
    const dest = await mkdtemp(path.join(os.tmpdir(), 'finch-tamper2-'));
    try {
      await expect(extractPack(parsed, dest)).rejects.toThrow(/Attachment att-1 sha256 mismatch/);
    } finally {
      await rm(dest, { recursive: true, force: true });
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('parsePack: rejects non-zip bytes', async () => {
  await expect(parsePack(new Uint8Array([0, 1, 2, 3]))).rejects.toThrow(/Not a valid zip/);
});

test('parsePack: rejects a zip with no manifest', async () => {
  const zip = new JSZip();
  zip.file('random.txt', 'hello');
  const bytes = await zip.generateAsync({ type: 'uint8array' });
  await expect(parsePack(bytes)).rejects.toThrow(/Missing manifest/);
});

test('detectFileKind: distinguishes zip vs sqlite vs unknown', () => {
  // Zip local-file header.
  expect(detectFileKind(new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0x00, 0x00]))).toBe('zip');
  // SQLite magic.
  const sqliteHead = Buffer.from('SQLite format 3\0' + 'X'.repeat(2));
  expect(detectFileKind(new Uint8Array(sqliteHead))).toBe('sqlite');
  // Random bytes.
  expect(detectFileKind(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]))).toBe('unknown');
  // Short input.
  expect(detectFileKind(new Uint8Array([0x50, 0x4b]))).toBe('unknown');
});

test('PACK_ATTACHMENTS_PREFIX is forward-slashed for cross-platform interop', () => {
  expect(PACK_ATTACHMENTS_PREFIX).toBe('attachments/');
});
