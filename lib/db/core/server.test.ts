import { test, expect } from 'bun:test';
import { bareDb, freshDb } from './test-utils';
import { assertCarryForwardable } from './server';

// A pre-double-entry finch database has a `categories` table that predates the
// equity `system` marker column. Opening it used to fail deep inside
// applySchema with the opaque SQLite error "no such column: system" (the
// idx_cat_system index references a column the old table lacks), 500-ing every
// read/write. assertCarryForwardable catches this shape up front and explains
// the remedy instead.

test('assertCarryForwardable rejects a pre-double-entry database with a clear, actionable error', async () => {
  const { exec } = await bareDb();
  // Minimal pre-DE shape: a `categories` table WITHOUT the `system` column.
  await exec(`CREATE TABLE categories (id TEXT PRIMARY KEY, ledger_id TEXT, name TEXT)`);

  let err: Error | null = null;
  try {
    await assertCarryForwardable(exec, '/some/dir/finch.sqlite3');
  } catch (e) {
    err = e as Error;
  }

  expect(err).not.toBeNull();
  // NOT the opaque SQLite failure.
  expect(err!.message).not.toMatch(/no such column/i);
  // Names the problem and the fix (delete the file to reseed).
  expect(err!.message).toMatch(/double-entry/i);
  expect(err!.message).toMatch(/finch\.sqlite3/);
});

test('assertCarryForwardable passes a current (post-double-entry) database', async () => {
  // The canonical schema gives `categories` the `system` column.
  const { exec } = await freshDb();
  await expect(assertCarryForwardable(exec, '/some/dir/finch.sqlite3')).resolves.toBeUndefined();
});

test('assertCarryForwardable is a no-op when there is no categories table yet (fresh file)', async () => {
  // A brand-new file has no tables; the guard must not misfire before the
  // canonical schema is applied.
  const { exec } = await bareDb();
  await expect(assertCarryForwardable(exec, '/some/dir/finch.sqlite3')).resolves.toBeUndefined();
});
