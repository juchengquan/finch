import { test, expect, beforeEach, afterEach } from 'bun:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { autoBackup, listBackups, _resetServerDbForTests } from '@/lib/db/server';

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

test('autoBackup writes a sibling .bak with timestamped name + SQLite content', async () => {
  process.env.FINCH_BACKUP_MIN_INTERVAL_MS = '0';
  const { path: backupPath } = await autoBackup();
  expect(backupPath.startsWith(tmpDir)).toBe(true);
  expect(path.basename(backupPath)).toMatch(/^finch-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z\.sqlite3\.bak$/);
  const buf = await fs.readFile(backupPath);
  expect(buf.subarray(0, 15).toString('latin1')).toBe('SQLite format 3');
  expect(buf[15]).toBe(0); // header terminator is a NUL byte
});

test('autoBackup throttle: second call within minInterval returns the same path', async () => {
  process.env.FINCH_BACKUP_MIN_INTERVAL_MS = '60000'; // 1 min
  const a = await autoBackup();
  const b = await autoBackup();
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
    const name = `finch-2025-01-0${i + 1}T00-00-00Z.sqlite3.bak`;
    const p = path.join(tmpDir, name);
    await fs.writeFile(p, Buffer.from('fake'));
    const past = new Date(Date.now() - (10 + i) * 86400000);
    await fs.utimes(p, past, past);
  }
  await autoBackup(); // real one — should retain 3 newest (incl. itself), prune 2
  const all = await listBackups();
  expect(all.length).toBe(3);
});

test('listBackups returns newest first', async () => {
  // Pre-populate two backups with explicit mtimes to skip the timestamp wait.
  const oldPath = path.join(tmpDir, 'finch-2025-01-01T00-00-00Z.sqlite3.bak');
  const newPath = path.join(tmpDir, 'finch-2026-01-01T00-00-00Z.sqlite3.bak');
  await fs.writeFile(oldPath, Buffer.from('a'));
  await fs.writeFile(newPath, Buffer.from('b'));
  await fs.utimes(oldPath, new Date('2025-01-01'), new Date('2025-01-01'));
  await fs.utimes(newPath, new Date('2026-01-01'), new Date('2026-01-01'));
  const all = await listBackups();
  expect(all.map((b) => b.name)).toEqual([
    'finch-2026-01-01T00-00-00Z.sqlite3.bak',
    'finch-2025-01-01T00-00-00Z.sqlite3.bak',
  ]);
});
