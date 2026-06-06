import { test, expect, beforeEach, afterEach } from 'bun:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  exportDbBytes,
  importDbBytes,
  validateImportBytes,
  listBackups,
  _resetServerDbForTests,
  getServerDb,
} from '@/lib/db/server';

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
  const db = await getServerDb();
  const [{ n }] = await db.exec('SELECT COUNT(*) AS n FROM transactions');
  expect(Number(n)).toBe(result.metadata.rowCounts?.transactions ?? -1);
});

test('importDbBytes rejects a tampered file (checksum mismatch)', async () => {
  // Export a clean file, then mutate a real row to invalidate the recorded
  // checksum without breaking the SQLite header itself.
  await getServerDb();
  const { bytes } = await exportDbBytes();
  const { openDb, execFor } = await import('./driver');
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
