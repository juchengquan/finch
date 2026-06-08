import { test, expect, beforeEach, afterEach } from 'bun:test';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// These env-var reads happen at module load (dbFile() reads process.env when
// getServerDb runs). We set them per-test in beforeEach and reset in
// afterEach to keep tests isolated from any prior server-state in the runner.
let tmpDir = '';

beforeEach(() => {
  tmpDir = mkdtempSync(join(tmpdir(), 'finch-server-audit-'));
  process.env.FINCH_DB_DIR = tmpDir;
  process.env.FINCH_DB_FILE = 'audit.sqlite3';
});

afterEach(async () => {
  // Drop the cached connection + audit cache so the next test (or the next
  // process boot) sees a clean slate.
  const { _resetServerDbForTests, _resetAuditCacheForTests } = await import('./server');
  _resetAuditCacheForTests();
  _resetServerDbForTests();
  rmSync(tmpDir, { recursive: true, force: true });
});

test('getCachedAudit populates the cache on first call', async () => {
  const { getCachedAudit } = await import('./server');
  const first = await getCachedAudit();
  expect(first.problemCount).toBe(0);
  expect(first.problems).toEqual([]);
  expect(typeof first.checkedAt).toBe('string');
  // checkedAt is an ISO 8601 string; verify it parses to a recent timestamp.
  const t = Date.parse(first.checkedAt);
  expect(Number.isFinite(t)).toBe(true);
  expect(Math.abs(Date.now() - t)).toBeLessThan(5_000);
});

test('getCachedAudit returns the cached value on subsequent calls', async () => {
  const { getCachedAudit } = await import('./server');
  const first = await getCachedAudit();
  // Second call should return the SAME checkedAt — proves the cache fired
  // (a fresh audit would generate a slightly later timestamp).
  const second = await getCachedAudit();
  expect(second.checkedAt).toBe(first.checkedAt);
  expect(second.problemCount).toBe(first.problemCount);
  expect(second.problems).toBe(first.problems);
});

test('getCachedAudit resets on cache clear', async () => {
  const { getCachedAudit, _resetAuditCacheForTests } = await import('./server');
  const first = await getCachedAudit();
  expect(typeof first.checkedAt).toBe('string');
  _resetAuditCacheForTests();
  // The second call repopulates the cache. Its checkedAt may share a
  // timestamp with `first` (sub-second resolution) — sleep just over a
  // second so the third call's timestamp is provably later.
  await getCachedAudit();
  await new Promise((r) => setTimeout(r, 1_100));
  const third = await getCachedAudit();
  expect(third.checkedAt).not.toBe(first.checkedAt);
});
