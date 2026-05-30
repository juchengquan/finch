import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema, migrate } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import { applyMutation } from '@/lib/db/mutations';
import { projectState } from '@/lib/db/state';
import { listBudgetGroups as listGroups } from '@/lib/db/queries/budgetGroups';
import type { Exec } from '@/lib/db/repo';

async function seeded(): Promise<Exec> {
  const sqlite3 = await (sqlite3InitModule as unknown as (o?: object) => ReturnType<typeof sqlite3InitModule>)({
    print() {},
    printErr() {},
  });
  const db = new sqlite3.oo1.DB(':memory:');
  const exec: Exec = async (sql, bind) => {
    const rows: Record<string, SqlValue>[] = [];
    db.exec({ sql, bind: (bind ?? []) as SqlValue[], rowMode: 'object', resultRows: rows });
    return rows;
  };
  await applySchema(exec);
  await seedDatabase(exec);
  await migrate(exec, { fresh: true });
  return exec;
}

test('createBudgetGroup + createBudget round-trips through projection', async () => {
  const exec = await seeded();

  await applyMutation(exec, 'createBudgetGroup', { id: 'bgg-1', ledgerId: 'personal', name: 'Living' });
  expect(await listGroups(exec, 'personal')).toHaveLength(1);

  await applyMutation(exec, 'createBudget', {
    id: 'bgt-1',
    ledgerId: 'personal',
    groupId: 'bgg-1',
    name: 'Groceries',
    type: 'expense',
    amount: 600,
    frequency: 'monthly',
    startDate: '2026-05-01',
    categoryIds: ['food'],
    accountIds: ['chk'],
  });

  const state = await projectState(exec);
  const b = state.budgets.find((x) => x.id === 'bgt-1')!;
  expect(b).toBeDefined();
  expect(b.name).toBe('Groceries');
  expect(b.type).toBe('expense');
  expect(b.groupId).toBe('bgg-1');
  expect(b.amount).toBe(600);
  expect(b.categoryIds).toEqual(['food']);
  expect(b.accountIds).toEqual(['chk']);
  expect(state.budgetGroups).toHaveLength(1);
});

test('contributeBudget accumulates and clamps a one-shot income budget', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-goal',
    ledgerId: 'personal',
    name: 'New car',
    type: 'income',
    amount: 30000,
    isRecurring: 0,
    frequency: 'monthly',
    startDate: '2026-01-15',
  });
  await applyMutation(exec, 'contributeBudget', { id: 'bgt-goal', amount: 1200 });
  await applyMutation(exec, 'contributeBudget', { id: 'bgt-goal', amount: -99999 }); // clamps at 0
  const b = (await projectState(exec)).budgets.find((x) => x.id === 'bgt-goal')!;
  expect(b.type).toBe('income');
  expect(b.isRecurring).toBe(0);
  expect(b.saved).toBe(0);
});

test('updateBudget patches fields; removeBudget deletes', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-2', ledgerId: 'personal', name: 'Fun', type: 'expense', amount: 100,
    frequency: 'monthly', startDate: '2026-05-01',
  });
  await applyMutation(exec, 'updateBudget', { id: 'bgt-2', patch: { name: 'Leisure', amount: 250, categoryIds: ['food', 'transport'] } });
  const b = (await projectState(exec)).budgets.find((x) => x.id === 'bgt-2')!;
  expect(b.name).toBe('Leisure');
  expect(b.amount).toBe(250);
  expect(b.categoryIds).toEqual(['food', 'transport']);

  await applyMutation(exec, 'removeBudget', { id: 'bgt-2' });
  expect((await projectState(exec)).budgets.some((x) => x.id === 'bgt-2')).toBe(false);
});

test('deleteBudgetGroup nulls its budgets group_id (FK SET NULL)', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudgetGroup', { id: 'bgg-x', ledgerId: 'personal', name: 'Bills' });
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-3', ledgerId: 'personal', groupId: 'bgg-x', name: 'Rent', type: 'expense', amount: 2000,
    frequency: 'monthly', startDate: '2026-05-01',
  });
  await applyMutation(exec, 'deleteBudgetGroup', { id: 'bgg-x' });
  const state = await projectState(exec);
  expect(state.budgetGroups).toHaveLength(0);
  expect(state.budgets.find((x) => x.id === 'bgt-3')!.groupId).toBeNull();
});

test('createBudget rejects empty name and non-positive amount', async () => {
  const exec = await seeded();
  await expect(
    applyMutation(exec, 'createBudget', { ledgerId: 'personal', name: '  ', type: 'expense', amount: 100, frequency: 'monthly', startDate: '2026-05-01' }),
  ).rejects.toThrow();
  await expect(
    applyMutation(exec, 'createBudget', { ledgerId: 'personal', name: 'X', type: 'expense', amount: 0, frequency: 'monthly', startDate: '2026-05-01' }),
  ).rejects.toThrow();
});
