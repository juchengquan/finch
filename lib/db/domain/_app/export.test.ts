import { test, expect } from 'bun:test';
import { seededAndAudited } from '@/lib/db/core/test-utils';
import { transactionExportRows } from '@/lib/db/queries/export';

test('export: transactionExportRows scopes by ledger and month', async () => {
  const exec = await seededAndAudited();

  const all = await transactionExportRows(exec);
  expect(all.length).toBeGreaterThan(0);

  // Ledger scope: every row belongs to the asked-for ledger.
  const personal = await transactionExportRows(exec, { ledgerId: 'personal' });
  expect(personal.length).toBeGreaterThan(0);
  expect(personal.every((r) => r.ledger === 'personal')).toBe(true);
  expect(personal.length).toBeLessThanOrEqual(all.length);

  // Month scope: every row's date is inside the asked-for month.
  const may = await transactionExportRows(exec, { ledgerId: 'personal', month: '2026-05' });
  expect(may.every((r) => r.date.startsWith('2026-05'))).toBe(true);
  expect(may.length).toBeLessThanOrEqual(personal.length);

  // A month with no data yields an empty export, not an error.
  const none = await transactionExportRows(exec, { ledgerId: 'personal', month: '1999-01' });
  expect(none).toEqual([]);
});
