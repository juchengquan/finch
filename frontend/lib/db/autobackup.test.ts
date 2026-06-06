import { test, expect, beforeEach, afterEach } from 'bun:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { autoBackup, listBackups, _resetServerDbForTests } from '@/lib/db/server';
import { detectFileKind } from '@/lib/db/pack';

// Each test gets a fresh tmp dir + resets the cached server connection so it
// reopens against that dir. Without the reset, the singleton would keep
// writing to whichever dir the first test happened to point at.

let tmpDir: string;
let originalDir: string | undefined;
let originalKeep: string | undefined;
let originalInterval: string | undefined;

beforeEach(async () => {
  originalDir = process.env.FINCH_DB_DIR;
  originalKeep = process.env.FINCH_BACKUP_KEEP;
  originalInterval = process.env.FINCH_BACKUP_MIN_INTERVAL_MS;
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'finch-autobackup-'));
  process.env.FINCH_DB_DIR = tmpDir;
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

test('autoBackup writes a sibling .finch.bak pack with timestamped name + zip content', async () => {
  process.env.FINCH_BACKUP_MIN_INTERVAL_MS = '0';
  const { path: backupPath, created } = await autoBackup();
  expect(created).toBe(true);
  expect(backupPath.startsWith(tmpDir)).toBe(true);
  expect(path.basename(backupPath)).toMatch(/^finch-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z\.finch\.bak$/);
  // Body is a .finch pack — first 4 bytes are the zip local-file header.
  const buf = await fs.readFile(backupPath);
  expect(detectFileKind(new Uint8Array(buf.subarray(0, 16)))).toBe('zip');
});

test('autoBackup throttle: second call within minInterval returns the same path with created=false', async () => {
  process.env.FINCH_BACKUP_MIN_INTERVAL_MS = '60000'; // 1 min
  const a = await autoBackup();
  const b = await autoBackup();
  expect(a.created).toBe(true);
  expect(b.created).toBe(false);
  expect(b.path).toBe(a.path);
  expect((await listBackups()).length).toBe(1);
});

test('autoBackup retention: prunes oldest beyond FINCH_BACKUP_KEEP', async () => {
  process.env.FINCH_BACKUP_MIN_INTERVAL_MS = '0';
  process.env.FINCH_BACKUP_KEEP = '3';
  // Drop 4 fake older backup files into the dir (with mtimes in the past so
  // listBackups() sorts them after the real one we're about to write). This
  // avoids the >1s/file wait that the second-precision timestamp would force.
  for (let i = 0; i < 4; i++) {
    const name = `finch-2025-01-0${i + 1}T00-00-00Z.finch.bak`;
    const p = path.join(tmpDir, name);
    await fs.writeFile(p, Buffer.from('fake'));
    const past = new Date(Date.now() - (10 + i) * 86400000);
    await fs.utimes(p, past, past);
  }
  await autoBackup(); // real one — should retain 3 newest (incl. itself), prune 2
  const all = await listBackups();
  expect(all.length).toBe(3);
});

test('listBackups returns newest first; mixes new .finch.bak and legacy .sqlite3.bak', async () => {
  // Two pre-populated backups: one in each format. Both should surface.
  const legacyPath = path.join(tmpDir, 'finch-2025-01-01T00-00-00Z.sqlite3.bak');
  const newPath = path.join(tmpDir, 'finch-2026-01-01T00-00-00Z.finch.bak');
  await fs.writeFile(legacyPath, Buffer.from('a'));
  await fs.writeFile(newPath, Buffer.from('b'));
  await fs.utimes(legacyPath, new Date('2025-01-01'), new Date('2025-01-01'));
  await fs.utimes(newPath, new Date('2026-01-01'), new Date('2026-01-01'));
  const all = await listBackups();
  expect(all.map((b) => b.name)).toEqual([
    'finch-2026-01-01T00-00-00Z.finch.bak',
    'finch-2025-01-01T00-00-00Z.sqlite3.bak',
  ]);
});

test('autoBackup when frequencyMs = -1 (off): returns created=false, no new file', async () => {
  // No env var; instead seed app_state with frequency=-1 so the runtime sees "off".
  // First boot the DB so app_state exists.
  process.env.FINCH_BACKUP_MIN_INTERVAL_MS = '0';
  await autoBackup({ force: true }); // sanity: forces one
  const before = (await listBackups()).length;
  expect(before).toBeGreaterThanOrEqual(1);

  // Now write the off setting via the mutation path (round-trip through the server).
  const { getServerDb } = await import('@/lib/db/server');
  const { setAppState } = await import('@/lib/db/queries/appState');
  const db = await getServerDb();
  await setAppState(db.exec, 'backupConfig', JSON.stringify({ frequencyMs: -1, retention: 14 }));

  const result = await autoBackup(); // not forced
  expect(result.created).toBe(false);
  // No new file was written — the count is unchanged from before.
  const after = await listBackups();
  expect(after.length).toBe(before);
});

test('autoBackup with force=true overrides both throttle AND off', async () => {
  process.env.FINCH_BACKUP_MIN_INTERVAL_MS = '60000';
  const a = await autoBackup({ force: true });
  expect(a.created).toBe(true);

  // Now flip to "off" via app_state.
  const { getServerDb } = await import('@/lib/db/server');
  const { setAppState } = await import('@/lib/db/queries/appState');
  const db = await getServerDb();
  await setAppState(db.exec, 'backupConfig', JSON.stringify({ frequencyMs: -1, retention: 14 }));

  // Sleep enough for a fresh timestamp (timestamp is per-second).
  await new Promise((r) => setTimeout(r, 1100));
  const b = await autoBackup({ force: true });
  expect(b.created).toBe(true);
  expect(b.path).not.toBe(a.path);
});
