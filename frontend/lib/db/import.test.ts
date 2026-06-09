import { test, expect, beforeEach, afterEach } from 'bun:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  exportDbBytes,
  importDbBytes,
  importPackBytes,
  validateImportBytes,
  listBackups,
  _resetServerDbForTests,
  getServerDb,
} from './core/server';
import { seededDb } from './core/test-utils';
import { buildPack } from './core/pack';

// Each test gets its own tmp data dir so files don't bleed across tests.

let tmpDir: string;
let originalDir: string | undefined;
let originalKeep: string | undefined;
let originalInterval: string | undefined;

beforeEach(async () => {
  originalDir = process.env.FINCH_DB_DIR;
  originalKeep = process.env.FINCH_BACKUP_KEEP;
  originalInterval = process.env.FINCH_BACKUP_MIN_INTERVAL_MS;
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'finch-import-'));
  process.env.FINCH_DB_DIR = tmpDir;
  process.env.FINCH_BACKUP_MIN_INTERVAL_MS = '0';
  _resetServerDbForTests();
});

afterEach(async () => {
  _resetServerDbForTests();
  if (originalDir === undefined) delete process.env.FINCH_DB_DIR;
  else process.env.FINCH_DB_DIR = originalDir;
  if (originalKeep === undefined) delete process.env.FINCH_BACKUP_KEEP;
  else process.env.FINCH_BACKUP_KEEP = originalKeep;
  if (originalInterval === undefined) delete process.env.FINCH_BACKUP_MIN_INTERVAL_MS;
  else process.env.FINCH_BACKUP_MIN_INTERVAL_MS = originalInterval;
  await fs.rm(tmpDir, { recursive: true, force: true });
});

test('validateImportBytes rejects a non-SQLite file with a clear reason', async () => {
  const v = await validateImportBytes(new Uint8Array(Buffer.from('not a sqlite file')));
  expect(v.ok).toBe(false);
  expect(v.reason).toMatch(/SQLite/i);
});

test('round-trip: export then import on a fresh process restores identical state', async () => {
  // Boot, get a row count and a known mutation, export.
  await getServerDb();
  const { bytes: stamped } = await exportDbBytes();
  expect(Buffer.from(stamped.subarray(0, 15)).toString('latin1')).toBe('SQLite format 3');

  // Throw away the live DB and force-restore from the bytes.
  _resetServerDbForTests();
  const result = await importDbBytes(stamped);
  expect(result.ok).toBe(true);
  expect(result.metadata.appName).toBe('finch');
  // The auto-backup snapshot lives in the same dir.
  expect(result.backupPath.startsWith(tmpDir)).toBe(true);

  // The reopened DB has the same row counts the export stamped.
  // §2: entries replaces transactions; CANONICAL_TABLES uses 'entries'.
  const db = await getServerDb();
  const [{ n }] = await db.exec('SELECT COUNT(*) AS n FROM entries');
  expect(Number(n)).toBe(result.metadata.rowCounts?.entries ?? -1);
});

test('importDbBytes rejects a tampered file (checksum mismatch)', async () => {
  // Export a clean file, then mutate a real row to invalidate the recorded
  // checksum without breaking the SQLite header itself.
  await getServerDb();
  const { bytes } = await exportDbBytes();
  const { openDb, execFor } = await import('./core/driver');
  const tamperPath = path.join(os.tmpdir(), `finch-tamper-${Date.now()}.sqlite3`);
  await fs.writeFile(tamperPath, Buffer.from(bytes));
  const driver = await openDb(tamperPath);
  try {
    const exec = execFor(driver);
    await exec("UPDATE accounts SET name = 'tampered' WHERE id = 'chk'");
    driver.exec('PRAGMA wal_checkpoint(TRUNCATE)');
  } finally {
    driver.close();
  }
  const tampered = new Uint8Array(await fs.readFile(tamperPath));
  await expect(importDbBytes(tampered)).rejects.toThrow(/checksum|corrupted|tamper/i);
  await fs.unlink(tamperPath).catch(() => {});
  await fs.unlink(`${tamperPath}-wal`).catch(() => {});
  await fs.unlink(`${tamperPath}-shm`).catch(() => {});
});

test('importDbBytes runs autoBackup before swapping', async () => {
  await getServerDb();
  expect((await listBackups()).length).toBe(0);
  const { bytes } = await exportDbBytes();
  await importDbBytes(bytes);
  const backups = await listBackups();
  expect(backups.length).toBe(1); // the autoBackup taken before the swap
});

test('importDbBytes rejects upload above FINCH_IMPORT_MAX_MB', async () => {
  process.env.FINCH_IMPORT_MAX_MB = '1'; // 1 MB cap
  // 2 MB of zero bytes — bigger than the cap, never reaches validation.
  const tooBig = new Uint8Array(2 * 1024 * 1024);
  await expect(importDbBytes(tooBig)).rejects.toThrow(/too large/i);
  delete process.env.FINCH_IMPORT_MAX_MB;
});

test('importDbBytes refuses an audit-failing DB and leaves the live DB untouched', async () => {
  // Boot the live server DB so we have a known-good file on disk to compare against.
  const liveDb = await getServerDb();
  const livePath = liveDb.file;

  // Build a separate in-memory DB with one unsealed entry — the cheapest
  // corruption the audit reliably detects. VACUUM INTO a tempfile to get
  // bytes that look like a real export.
  const tmp = path.join(
    os.tmpdir(),
    `finch-bad-${Date.now()}-${Math.random().toString(36).slice(2)}.sqlite3`,
  );
  const { exec, driver, close } = await seededDb();
  try {
    await exec(
      `INSERT INTO entries (id, ledger_id, date, kind, status, sealed, created_at, updated_at)
       VALUES ('e-bad', 'personal', '2026-06-07', 'expense', 'confirmed', 0, datetime('now'), datetime('now'))`,
    );
    await exec(
      `INSERT INTO postings (id, entry_id, account_id, amount, currency, amount_base, exchange_rate)
       VALUES ('p-bad-a', 'e-bad', 'chk', -10, 'USD', -10, 1)`,
    );
    driver.prepare('VACUUM INTO ?').run(tmp);
    const bytes = new Uint8Array(await fs.readFile(tmp));

    // Snapshot the live DB before the import.
    const liveBefore = await fs.readFile(livePath);

    await expect(importDbBytes(bytes)).rejects.toThrow(/audit|unsealed|unbalanced/i);

    // Live DB unchanged.
    const liveAfter = await fs.readFile(livePath);
    expect(Buffer.compare(liveBefore, liveAfter)).toBe(0);
  } finally {
    close();
    await fs.unlink(tmp).catch(() => {});
    await fs.unlink(`${tmp}-wal`).catch(() => {});
    await fs.unlink(`${tmp}-shm`).catch(() => {});
  }
});

test('importPackBytes refuses an audit-failing pack, leaves the live DB untouched, and tears down the staging dir', async () => {
  // Boot the live server DB so we have a known-good file on disk to compare against.
  const liveDb = await getServerDb();
  const livePath = liveDb.file;

  // Build a separate in-memory DB with one unsealed entry, VACUUM INTO a
  // tempfile, and wrap those bytes in a real `.finch` pack via buildPack.
  // This exercises the full pack import path (parse + extract + audit),
  // not just the bare-DB one covered above.
  const dbTmp = path.join(
    os.tmpdir(),
    `finch-bad-pack-db-${Date.now()}-${Math.random().toString(36).slice(2)}.sqlite3`,
  );
  const { exec, driver, close } = await seededDb();
  let packBytes: Uint8Array;
  try {
    await exec(
      `INSERT INTO entries (id, ledger_id, date, kind, status, sealed, created_at, updated_at)
       VALUES ('e-bad', 'personal', '2026-06-07', 'expense', 'confirmed', 0, datetime('now'), datetime('now'))`,
    );
    await exec(
      `INSERT INTO postings (id, entry_id, account_id, amount, currency, amount_base, exchange_rate)
       VALUES ('p-bad-a', 'e-bad', 'chk', -10, 'USD', -10, 1)`,
    );
    driver.prepare('VACUUM INTO ?').run(dbTmp);
    const dbBytes = new Uint8Array(await fs.readFile(dbTmp));

    const built = await buildPack({
      dbBytes,
      // Empty attachments list keeps the test small — the pack still
      // round-trips through parsePack + extractPack + the audit gate.
      attachmentFiles: [],
      meta: {
        appVersion: 'test',
        schemaVersion: '2026-06-14T00:00:00Z',
        exportedAt: '2026-06-08T00:00:00.000Z',
        rowCounts: {},
      },
    });
    packBytes = built.bytes;
  } finally {
    close();
    await fs.unlink(dbTmp).catch(() => {});
    await fs.unlink(`${dbTmp}-wal`).catch(() => {});
    await fs.unlink(`${dbTmp}-shm`).catch(() => {});
  }

  // Snapshot the live DB before the import.
  const liveBefore = await fs.readFile(livePath);

  // Snapshot any pre-existing `finch-pack-import-*` dirs so we can
  // distinguish leftover artefacts from this test's staging dir. (Other
  // tests use different prefixes — pack.test.ts uses `finch-pack-test-` etc.)
  const beforeDirs = new Set(
    (await fs.readdir(os.tmpdir(), { withFileTypes: true }))
      .filter((d) => d.isDirectory() && d.name.startsWith('finch-pack-import-'))
      .map((d) => d.name),
  );

  await expect(importPackBytes(packBytes!)).rejects.toThrow(/audit|unsealed|unbalanced/i);

  // Live DB byte-identical — audit gate must abort before any swap.
  const liveAfter = await fs.readFile(livePath);
  expect(Buffer.compare(liveBefore, liveAfter)).toBe(0);

  // Staging dir torn down. The function populates `<os.tmpdir()>/finch-pack-import-…`
  // via extractPack and should rm it on EVERY rejection path, including
  // the audit gate. Any new entry in `finch-pack-import-*` after the import
  // is a leak.
  const afterDirs = (await fs.readdir(os.tmpdir(), { withFileTypes: true }))
    .filter((d) => d.isDirectory() && d.name.startsWith('finch-pack-import-'))
    .map((d) => d.name);
  const leaked = afterDirs.filter((n) => !beforeDirs.has(n));
  expect(leaked).toEqual([]);
});
