import { test, expect } from 'bun:test';
import { migrate } from './core/schema';
import { applyMutation } from '@/lib/db/mutate';
import { projectState } from '@/lib/db/state';
import { listBudgetGroups as listGroups } from '@/lib/db/queries/budgetGroups';
import { seededDb } from './core/test-utils';
import type { Exec } from './core/repo';

async function seeded(): Promise<Exec> {
  const { exec } = await seededDb();
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

test('updateBudget with amount-only patch stages to pending_amount on recurring budgets', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-stage', ledgerId: 'personal', name: 'Groceries', type: 'expense', amount: 700,
    frequency: 'monthly', startDate: '2026-05-01',
  });
  await applyMutation(exec, 'updateBudget', { id: 'bgt-stage', patch: { amount: 800 } });
  const [row] = await exec("SELECT amount, pending_amount FROM budgets WHERE id = 'bgt-stage'");
  expect(Number(row.amount)).toBe(700);            // active unchanged
  expect(Number(row.pending_amount)).toBe(800);    // staged

  // Subsequent amount-only edit overwrites the staged value.
  await applyMutation(exec, 'updateBudget', { id: 'bgt-stage', patch: { amount: 850 } });
  const [row2] = await exec("SELECT amount, pending_amount FROM budgets WHERE id = 'bgt-stage'");
  expect(Number(row2.pending_amount)).toBe(850);
});

test('updateBudget with amount + other fields applies amount immediately', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-multi', ledgerId: 'personal', name: 'X', type: 'expense', amount: 500,
    frequency: 'monthly', startDate: '2026-05-01',
  });
  await applyMutation(exec, 'updateBudget', {
    id: 'bgt-multi', patch: { amount: 600, categoryIds: ['food'] },
  });
  const [row] = await exec("SELECT amount, pending_amount FROM budgets WHERE id = 'bgt-multi'");
  expect(Number(row.amount)).toBe(600);            // applied
  expect(row.pending_amount).toBeNull();           // not staged
});

test('updateBudget on a one-shot (is_recurring=0) budget applies amount immediately', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-oneshot', ledgerId: 'personal', name: 'Goal', type: 'income', amount: 5000,
    frequency: 'monthly', startDate: '2026-05-01', isRecurring: 0,
  });
  await applyMutation(exec, 'updateBudget', { id: 'bgt-oneshot', patch: { amount: 6000 } });
  const [row] = await exec("SELECT amount, pending_amount FROM budgets WHERE id = 'bgt-oneshot'");
  expect(Number(row.amount)).toBe(6000);
  expect(row.pending_amount).toBeNull();
});

test('updateBudgetCycle writes amount + cycle + clears pending + resets last_rolled', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-cyc', ledgerId: 'personal', name: 'Food', type: 'expense', amount: 700,
    frequency: 'monthly', startDate: '2026-05-01',
  });
  // Pre-populate pending_amount + last_rolled_period to verify the wipe.
  await exec("UPDATE budgets SET pending_amount = 950, last_rolled_period = '2026-04-01', carry_forward = 80 WHERE id = 'bgt-cyc'");

  await applyMutation(exec, 'updateBudgetCycle', {
    id: 'bgt-cyc',
    patch: { frequency: 'weekly', startDate: '2026-05-04', amount: 175 },
  });

  const [row] = await exec("SELECT amount, frequency, start_date, pending_amount, last_rolled_period, carry_forward FROM budgets WHERE id = 'bgt-cyc'");
  expect(Number(row.amount)).toBe(175);
  expect(String(row.frequency)).toBe('weekly');
  expect(String(row.start_date)).toBe('2026-05-04');
  expect(row.pending_amount).toBeNull();
  expect(row.last_rolled_period).toBeNull();
  expect(Number(row.carry_forward)).toBe(80); // preserved
});

test('updateBudgetCycle without amount keeps the existing amount', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-cyc2', ledgerId: 'personal', name: 'Food', type: 'expense', amount: 700,
    frequency: 'monthly', startDate: '2026-05-01',
  });
  await applyMutation(exec, 'updateBudgetCycle', {
    id: 'bgt-cyc2', patch: { frequency: 'weekly', startDate: '2026-05-04' },
  });
  const [row] = await exec("SELECT amount FROM budgets WHERE id = 'bgt-cyc2'");
  expect(Number(row.amount)).toBe(700); // unchanged
});

test('updateBudgetCycle rejects unknown frequency or malformed startDate', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-cyc3', ledgerId: 'personal', name: 'X', type: 'expense', amount: 100,
    frequency: 'monthly', startDate: '2026-05-01',
  });
  await expect(applyMutation(exec, 'updateBudgetCycle', {
    id: 'bgt-cyc3', patch: { frequency: 'fortnightly', startDate: '2026-05-04' },
  })).rejects.toThrow(/frequency/i);
  await expect(applyMutation(exec, 'updateBudgetCycle', {
    id: 'bgt-cyc3', patch: { frequency: 'weekly', startDate: '2026/05/04' },
  })).rejects.toThrow(/startDate|YYYY/i);
});

test('clearPendingAmount drops the staged value without touching active amount', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-clear', ledgerId: 'personal', name: 'X', type: 'expense', amount: 700,
    frequency: 'monthly', startDate: '2026-05-01',
  });
  await applyMutation(exec, 'updateBudget', { id: 'bgt-clear', patch: { amount: 800 } });
  await applyMutation(exec, 'clearPendingAmount', { id: 'bgt-clear' });
  const [row] = await exec("SELECT amount, pending_amount FROM budgets WHERE id = 'bgt-clear'");
  expect(Number(row.amount)).toBe(700);
  expect(row.pending_amount).toBeNull();
});

test('addTransaction backdated into a rolled period invalidates that budget', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-inv-1', ledgerId: 'personal', name: 'Food', type: 'expense', amount: 700,
    frequency: 'monthly', startDate: '2026-04-01', categoryIds: ['food'], rollover: 1,
  });
  // Pretend we already rolled April.
  await exec("UPDATE budgets SET last_rolled_period = '2026-04-01', carry_forward = 300 WHERE id = 'bgt-inv-1'");

  // Backdated April food tx → invalidate.
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -50, currency: 'USD',
    merchant: 'late entry', categoryId: 'food', date: '2026-04-10',
  });

  const [row] = await exec("SELECT last_rolled_period, carry_forward FROM budgets WHERE id = 'bgt-inv-1'");
  expect(row.last_rolled_period).toBeNull();
  expect(Number(row.carry_forward)).toBe(0);
});

test('addTransaction in the current period leaves rolled state untouched', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-inv-2', ledgerId: 'personal', name: 'Food', type: 'expense', amount: 700,
    frequency: 'monthly', startDate: '2026-04-01', categoryIds: ['food'], rollover: 1,
  });
  await exec("UPDATE budgets SET last_rolled_period = '2026-04-01', carry_forward = 300 WHERE id = 'bgt-inv-2'");

  // A May tx (current period, not yet rolled) doesn't invalidate.
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -30, currency: 'USD',
    merchant: 'current month', categoryId: 'food', date: '2026-05-15',
  });

  const [row] = await exec("SELECT last_rolled_period, carry_forward FROM budgets WHERE id = 'bgt-inv-2'");
  expect(String(row.last_rolled_period)).toBe('2026-04-01');
  expect(Number(row.carry_forward)).toBe(300);
});

// Applying a rule to past transactions moves their spend between budgets just
// as an edit does, so it must reset the cached rollover on both sides. It
// reset neither: Food kept carrying forward April money that had left it.
async function rolledFoodAndShop(exec: Exec) {
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -50, currency: 'USD',
    merchant: 'Zephyr Corner Shop', categoryId: 'food', date: '2026-04-10', skipRules: true,
  });
  for (const [id, cat] of [['bgt-food', 'food'], ['bgt-shop', 'shop']] as const) {
    await applyMutation(exec, 'createBudget', {
      id, ledgerId: 'personal', name: id, type: 'expense', amount: 700,
      frequency: 'monthly', startDate: '2026-04-01', categoryIds: [cat], rollover: 1,
    });
  }
  // Rolled after the purchase was entered, as a later launch would.
  await exec("UPDATE budgets SET last_rolled_period = '2026-04-01', carry_forward = 300 WHERE id IN ('bgt-food', 'bgt-shop')");
}

async function rolledPeriods(exec: Exec) {
  const rows = await exec("SELECT id, last_rolled_period FROM budgets WHERE id IN ('bgt-food', 'bgt-shop') ORDER BY id");
  return Object.fromEntries(rows.map((r) => [String(r.id), r.last_rolled_period]));
}

test('backfilling a re-categorizing rule invalidates the budgets it moves spend between', async () => {
  const exec = await seeded();
  await rolledFoodAndShop(exec);
  await applyMutation(exec, 'createRule', {
    id: 'r-shop', ledgerId: 'personal',
    condition: { field: 'merchant', op: 'contains', value: 'Zephyr' },
    actions: [{ type: 'set_category', categoryId: 'shop' }],
  });
  await applyMutation(exec, 'backfillRule', { id: 'r-shop' });
  expect(await rolledPeriods(exec)).toEqual({ 'bgt-food': null, 'bgt-shop': null });
});

test('backfilling a rule that leaves spend alone keeps the rolled state', async () => {
  const exec = await seeded();
  await rolledFoodAndShop(exec);
  await applyMutation(exec, 'createRule', {
    id: 'r-name', ledgerId: 'personal',
    condition: { field: 'merchant', op: 'contains', value: 'Zephyr' },
    actions: [{ type: 'set_merchant', merchant: 'Zephyr Corner Shop Co' }],
  });
  await applyMutation(exec, 'backfillRule', { id: 'r-name' });
  expect(await exec("SELECT description FROM entries WHERE description = 'Zephyr Corner Shop Co'")).toHaveLength(1);
  expect(await rolledPeriods(exec)).toEqual({ 'bgt-food': '2026-04-01', 'bgt-shop': '2026-04-01' });
});

test('deleteTransaction backdated into a rolled period invalidates', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'createBudget', {
    id: 'bgt-inv-3', ledgerId: 'personal', name: 'Food', type: 'expense', amount: 700,
    frequency: 'monthly', startDate: '2026-04-01', categoryIds: ['food'], rollover: 1,
  });
  // Add an April tx, mark budget as rolled, then delete the tx (backdated effect).
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: -100, currency: 'USD',
    merchant: 'X', categoryId: 'food', date: '2026-04-10',
  });
  const [tx] = await exec("SELECT id FROM entries WHERE description = 'X' LIMIT 1");
  const txId = String(tx.id);
  await exec("UPDATE budgets SET last_rolled_period = '2026-04-01', carry_forward = 200 WHERE id = 'bgt-inv-3'");
  await applyMutation(exec, 'deleteTransaction', { id: txId });
  const [row] = await exec("SELECT last_rolled_period FROM budgets WHERE id = 'bgt-inv-3'");
  expect(row.last_rolled_period).toBeNull();
});
