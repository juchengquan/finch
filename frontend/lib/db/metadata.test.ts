import { test, expect } from 'bun:test';
import { migrate, SCHEMA_VERSION } from '@/lib/db/schema';
import { readMetadata, rowCounts, stampExport } from '@/lib/db/queries/metadata';
import { computeChecksum } from '@/lib/db/checksum';
import { seededDb } from '@/lib/db/test-utils';
import type { Exec } from '@/lib/db/repo';

async function fresh(): Promise<Exec> {
  const { exec } = await seededDb();
  await migrate(exec, { fresh: true });
  return exec;
}

test('fresh DB carries a db_metadata row stamped with the schema version', async () => {
  const exec = await fresh();
  const meta = await readMetadata(exec);
  expect(meta).not.toBeNull();
  expect(meta!.appName).toBe('finch');
  expect(meta!.schemaVersion).toBe(SCHEMA_VERSION);
  expect(meta!.exportedAt).toBeNull();
  expect(meta!.checksum).toBeNull();
  // ISO 8601 — string is sortable and reversible.
  expect(meta!.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/);
});

test('rowCounts reports a count per canonical table; missing tables are 0', async () => {
  const exec = await fresh();
  const counts = await rowCounts(exec);
  expect(counts.transactions).toBeGreaterThan(0);
  expect(counts.accounts).toBeGreaterThan(0);
  expect(counts.categories).toBeGreaterThan(0);
  // Tables we know exist but might be empty are still reported (>= 0).
  expect(counts.transaction_splits).toBe(0);
});

test('computeChecksum is deterministic and changes when a row changes', async () => {
  const exec = await fresh();
  const a = await computeChecksum(exec);
  const b = await computeChecksum(exec);
  expect(a).toBe(b);
  expect(a).toMatch(/^[a-f0-9]{64}$/); // SHA-256 hex

  // Mutating data flips the hash.
  await exec("UPDATE accounts SET name = 'Renamed' WHERE id = 'chk'");
  const c = await computeChecksum(exec);
  expect(c).not.toBe(a);
});

test('computeChecksum ignores db_metadata writes (otherwise it self-references)', async () => {
  const exec = await fresh();
  const before = await computeChecksum(exec);
  await stampExport(exec, {
    exportedAt: '2026-05-30T08:15:30Z',
    exportedFrom: 'host-a',
    rowCounts: { transactions: 1 },
    checksum: 'placeholder',
  });
  const after = await computeChecksum(exec);
  expect(after).toBe(before);
});

test('persist flow: stampExport writes provenance the next read can see', async () => {
  const exec = await fresh();
  const counts = await rowCounts(exec);
  const checksum = await computeChecksum(exec);
  await stampExport(exec, {
    exportedAt: '2026-05-30T08:15:30Z',
    exportedFrom: 'host-x',
    rowCounts: counts,
    checksum,
  });
  const meta = await readMetadata(exec);
  expect(meta!.exportedAt).toBe('2026-05-30T08:15:30Z');
  expect(meta!.exportedFrom).toBe('host-x');
  expect(meta!.checksum).toBe(checksum);
  expect(meta!.rowCounts?.transactions).toBe(counts.transactions);
});
