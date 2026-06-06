import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import { createRule } from '@/lib/db/queries/rules';
import { insertTxRow } from '@/lib/db/queries/transactions';
import type { Exec } from '@/lib/db/repo';
import type { Action, Condition } from '@/lib/rules/types';

const initSqlite = sqlite3InitModule as unknown as (
  opts?: { print?: () => void; printErr?: () => void },
) => ReturnType<typeof sqlite3InitModule>;

async function seeded(): Promise<Exec> {
  const sqlite3 = await initSqlite({ print() {}, printErr() {} });
  const db = new sqlite3.oo1.DB(':memory:');
  const exec: Exec = async (sql, bind) => {
    const rows: Record<string, SqlValue>[] = [];
    db.exec({ sql, bind: (bind ?? []) as SqlValue[], rowMode: 'object', resultRows: rows });
    return rows;
  };
  await applySchema(exec);
  await seedDatabase(exec);
  return exec;
}

const baseRow = {
  ledgerId: 'personal',
  accountId: 'chk',
  date: '2026-05-15',
  amount: -40,
  description: 'Test',
  kind: 'expense' as const,
};

test('insertTxRow: a matching rule pre-categorises the row and records applied_rule_ids', async () => {
  const exec = await seeded();
  const cond: Condition = { field: 'merchant', op: 'contains', value: 'shell' };
  const actions: Action[] = [{ type: 'set_category', categoryId: 'trans' }];
  await createRule(exec, 'shell-fuel', { ledgerId: 'personal', condition: cond, actions });

  const id = await insertTxRow(exec, { ...baseRow, description: 'Shell #247', categoryId: null });
  const [row] = await exec(
    'SELECT category_id, applied_rule_ids FROM transactions WHERE id = ?',
    [id],
  );
  expect(String(row.category_id)).toBe('trans');
  expect(JSON.parse(String(row.applied_rule_ids))).toEqual(['shell-fuel']);
});

test('insertTxRow: amount-aware rules — Shell under $5 = Snacks, over = Fuel', async () => {
  const exec = await seeded();
  await createRule(exec, 'shell-snack', {
    ledgerId: 'personal',
    priority: 50, // lower number = runs first
    condition: {
      all: [
        { field: 'merchant', op: 'contains', value: 'shell' },
        { field: 'amount', op: 'lt', value: 5 },
      ],
    },
    actions: [{ type: 'set_category', categoryId: 'food' }],
  });
  await createRule(exec, 'shell-fuel', {
    ledgerId: 'personal',
    priority: 60,
    condition: {
      all: [
        { field: 'merchant', op: 'contains', value: 'shell' },
        { field: 'amount', op: 'gte', value: 5 },
      ],
    },
    actions: [{ type: 'set_category', categoryId: 'trans' }],
  });

  const snackId = await insertTxRow(exec, { ...baseRow, description: 'Shell', amount: -4.5 });
  const fuelId = await insertTxRow(exec, { ...baseRow, description: 'Shell', amount: -48 });
  const [snack] = await exec('SELECT category_id FROM transactions WHERE id = ?', [snackId]);
  const [fuel] = await exec('SELECT category_id FROM transactions WHERE id = ?', [fuelId]);
  expect(String(snack.category_id)).toBe('food');
  expect(String(fuel.category_id)).toBe('trans');
});

test('insertTxRow: tag-add action inserts a transaction_tags row after the parent lands', async () => {
  const exec = await seeded();
  await createRule(exec, 'biz-tag', {
    ledgerId: 'personal',
    condition: { field: 'note', op: 'contains', value: 'client' },
    actions: [{ type: 'add_tag', tagId: 'tag-business' }],
  });

  const id = await insertTxRow(exec, { ...baseRow, notes: 'Lunch with client' });
  const tags = await exec(
    'SELECT tag_id FROM transaction_tags WHERE transaction_id = ?',
    [id],
  );
  expect(tags.map((r) => String(r.tag_id))).toEqual(['tag-business']);
});

test('insertTxRow: split-action lays down transaction_splits summing to the parent', async () => {
  const exec = await seeded();
  await createRule(exec, 'target-split', {
    ledgerId: 'personal',
    condition: { field: 'merchant', op: 'contains', value: 'target' },
    actions: [
      {
        type: 'split',
        splits: [
          { fraction: 0.6, categoryId: 'food' },
          { fraction: 0.4, categoryId: 'shop' },
        ],
      },
    ],
  });

  const id = await insertTxRow(exec, { ...baseRow, description: 'Target', amount: -100 });
  const splits = await exec(
    'SELECT category_id, amount, amount_base FROM transaction_splits WHERE transaction_id = ? ORDER BY sort_order',
    [id],
  );
  expect(splits.map((s) => String(s.category_id))).toEqual(['food', 'shop']);
  // Sum of native amounts equals the parent's native amount.
  const sum = splits.reduce((s, r) => s + Number(r.amount), 0);
  expect(Math.round(sum * 100) / 100).toBe(-100);
});

test('insertTxRow: skipRules bypasses the engine entirely', async () => {
  const exec = await seeded();
  await createRule(exec, 'shell-fuel', {
    ledgerId: 'personal',
    condition: { field: 'merchant', op: 'contains', value: 'shell' },
    actions: [{ type: 'set_category', categoryId: 'trans' }],
  });
  const id = await insertTxRow(exec, {
    ...baseRow,
    description: 'Shell',
    categoryId: 'misc',
    skipRules: true,
  });
  const [row] = await exec(
    'SELECT category_id, applied_rule_ids FROM transactions WHERE id = ?',
    [id],
  );
  expect(String(row.category_id)).toBe('misc'); // untouched
  expect(row.applied_rule_ids).toBeNull();
});

test('insertTxRow: an inactive rule does not contribute', async () => {
  const exec = await seeded();
  await createRule(exec, 'off', {
    ledgerId: 'personal',
    isActive: false,
    condition: { field: 'merchant', op: 'contains', value: 'shell' },
    actions: [{ type: 'set_category', categoryId: 'trans' }],
  });
  const id = await insertTxRow(exec, { ...baseRow, description: 'Shell', categoryId: 'misc' });
  const [row] = await exec(
    'SELECT category_id, applied_rule_ids FROM transactions WHERE id = ?',
    [id],
  );
  expect(String(row.category_id)).toBe('misc');
  expect(row.applied_rule_ids).toBeNull();
});

test('insertTxRow: rule from a different ledger does not fire', async () => {
  const exec = await seeded();
  await createRule(exec, 'fam-tag', {
    ledgerId: 'family', // not 'personal'
    condition: { field: 'merchant', op: 'contains', value: 'shell' },
    actions: [{ type: 'set_category', categoryId: 'food' }],
  });
  const id = await insertTxRow(exec, { ...baseRow, description: 'Shell', categoryId: 'misc' });
  const [row] = await exec('SELECT category_id FROM transactions WHERE id = ?', [id]);
  expect(String(row.category_id)).toBe('misc');
});

test('insertTxRow: a later (higher-priority-number) rule overrides an earlier set_category', async () => {
  const exec = await seeded();
  await createRule(exec, 'early', {
    ledgerId: 'personal',
    priority: 10,
    condition: { field: 'merchant', op: 'contains', value: 'whole' },
    actions: [{ type: 'set_category', categoryId: 'food' }],
  });
  await createRule(exec, 'late', {
    ledgerId: 'personal',
    priority: 100,
    condition: { field: 'merchant', op: 'contains', value: 'whole' },
    actions: [{ type: 'set_category', categoryId: 'shop' }],
  });
  const id = await insertTxRow(exec, { ...baseRow, description: 'Whole Foods' });
  const [row] = await exec(
    'SELECT category_id, applied_rule_ids FROM transactions WHERE id = ?',
    [id],
  );
  expect(String(row.category_id)).toBe('shop');
  // Both ids in apply order — losing rule still recorded.
  expect(JSON.parse(String(row.applied_rule_ids))).toEqual(['early', 'late']);
});
