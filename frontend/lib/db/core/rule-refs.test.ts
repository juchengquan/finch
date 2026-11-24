import { test, expect } from 'bun:test';
import { applyMutation } from '@/lib/db/mutate';
import { seededDb } from '@/lib/db/core/test-utils';
import { auditLedger } from '@/lib/db/core/entries';
import type { Action, Condition } from '@/lib/rules/types';

// A rule names categories, merchants and tags by id. Deleting one of them left the
// rule pointing at nothing, and the next matching write died on the FOREIGN KEY
// check. Mirrors FinchCore's RuleRefsTests.
const market: Condition = { field: 'merchant', op: 'contains', value: 'Market' };

async function withCategory(exec: Awaited<ReturnType<typeof seededDb>>['exec'], id: string) {
  await applyMutation(exec, 'createCategory', { id, ledgerId: 'personal', name: id, kind: 'expense' });
}

test('a rule naming a deleted category, merchant and tag no longer blocks the write', async () => {
  const { exec } = await seededDb();
  await withCategory(exec, 'c-gone');
  await applyMutation(exec, 'createTag', { id: 't-gone', ledgerId: 'personal', name: 'gone' });
  await applyMutation(exec, 'createCounterparty', { id: 'cp-gone', name: 'Gone Market' });
  const actions: Action[] = [
    { type: 'set_category', categoryId: 'c-gone' },
    { type: 'set_counterparty', counterpartyId: 'cp-gone' },
    { type: 'add_tag', tagId: 't-gone' },
    { type: 'set_note', note: 'weekly shop' },
  ];
  await applyMutation(exec, 'createRule', { id: 'r1', ledgerId: 'personal', condition: market, actions });
  await applyMutation(exec, 'deleteCategory', { id: 'c-gone' });
  await applyMutation(exec, 'deleteCounterparty', { id: 'cp-gone' });
  await applyMutation(exec, 'deleteTag', { id: 't-gone' });

  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -12, merchant: 'Farmers Market',
    categoryId: 'food', date: '2026-06-02',
  });
  const [row] = await exec(
    `SELECT e.notes, p.category_id FROM entries e JOIN postings p ON p.entry_id = e.id
      WHERE e.description = 'Farmers Market' AND p.account_id IS NULL`,
  );
  expect(String(row.category_id)).toBe('food');
  expect(String(row.notes)).toBe('weekly shop');
});

test('backfill never writes a kind the entry cannot have', async () => {
  const { exec } = await seededDb();
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -12, merchant: 'Farmers Market',
    categoryId: 'food', date: '2026-06-02', skipRules: true,
  });
  for (const [id, kind] of [['r1', 'transfer'], ['r2', 'adjustment'], ['r3', 'refund']] as const) {
    await applyMutation(exec, 'createRule', {
      id, ledgerId: 'personal', condition: market, actions: [{ type: 'set_kind', kind }],
    });
    await applyMutation(exec, 'backfillRule', { id });
  }
  const [row] = await exec("SELECT kind FROM entries WHERE description = 'Farmers Market'");
  expect(String(row.kind)).toBe('expense');
  expect((await auditLedger(exec, 'personal')).filter((p) => p.code === 'kind-shape')).toEqual([]);
});
