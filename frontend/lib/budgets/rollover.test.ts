import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema, migrate } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import { rollBudgetsIfDue, invalidateRollover } from '@/lib/budgets/rollover';
import type { Exec } from '@/lib/db/repo';

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
  await migrate(exec, { fresh: true });
  return exec;
}

// Insert a recurring expense budget keyed by `id` with the given cycle setup.
async function insertBudget(
  exec: Exec,
  id: string,
  opts: {
    amount?: number;
    frequency?: string;
    startDate?: string;
    rollover?: 0 | 1;
    rolloverLimit?: number | null;
    categoryIds?: string[];
    isRecurring?: 0 | 1;
    type?: 'income' | 'expense';
  } = {},
) {
  const amount = opts.amount ?? 700;
  const frequency = opts.frequency ?? 'monthly';
  const startDate = opts.startDate ?? '2026-04-01';
  const rollover = opts.rollover ?? 0;
  const rolloverLimit = opts.rolloverLimit ?? null;
  const categoryIds = opts.categoryIds ?? ['food'];
  const isRecurring = opts.isRecurring ?? 1;
  const type = opts.type ?? 'expense';
  await exec(
    `INSERT INTO budgets
       (id, ledger_id, name, type, amount, carry_forward, frequency, start_date,
        is_recurring, rollover, rollover_limit, account_ids, category_ids,
        warning_pct, created_at, updated_at)
     VALUES (?, 'personal', ?, ?, ?, 0, ?, ?, ?, ?, ?, NULL, ?, 80, '2026-01-01', '2026-01-01')`,
    [
      id, id, type, amount, frequency, startDate, isRecurring, rollover,
      rolloverLimit, JSON.stringify(categoryIds),
    ],
  );
}

async function readBudget(exec: Exec, id: string) {
  const [row] = await exec(
    `SELECT amount, carry_forward, pending_amount, last_rolled_period
       FROM budgets WHERE id = ?`,
    [id],
  );
  return {
    amount: Number(row.amount),
    carryForward: Number(row.carry_forward ?? 0),
    pendingAmount: row.pending_amount == null ? null : Number(row.pending_amount),
    lastRolledPeriod: row.last_rolled_period == null ? null : String(row.last_rolled_period),
  };
}

test('rollBudgetsIfDue is a no-op when no period has closed since start_date', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-noop', { startDate: '2026-05-15' });
  const result = await rollBudgetsIfDue(exec, '2026-05-15');
  expect(result.rolled).toBe(0);
  const b = await readBudget(exec, 'b-noop');
  expect(b.lastRolledPeriod).toBeNull();
});

test('rollover OFF: just advances last_rolled_period', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-off', { rollover: 0 });
  const result = await rollBudgetsIfDue(exec, '2026-05-15');
  expect(result.rolled).toBeGreaterThan(0);
  const b = await readBudget(exec, 'b-off');
  expect(b.lastRolledPeriod).toBe('2026-04-01');
  expect(b.carryForward).toBe(0);
});

test('rollover ON: April leftover becomes May carry_forward', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-on', { amount: 700, rollover: 1, categoryIds: ['food'] });
  // Wipe seeded April food txns, replace with a controlled $400 spend.
  await exec("DELETE FROM transactions WHERE category_id = 'food' AND date BETWEEN '2026-04-01' AND '2026-04-30'");
  await exec(
    `INSERT INTO transactions (id,ledger_id,account_id,date,amount,amount_base,exchange_rate,description,category_id,status,currency,created_at,updated_at)
     VALUES ('t-apr-1','personal','chk','2026-04-10',-400,-400,1,'Groceries','food','confirmed','USD','2026-04-10','2026-04-10')`,
  );
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'b-on');
  expect(b.lastRolledPeriod).toBe('2026-04-01');
  // effective = 700 + 0 = 700; spent = 400; leftover = 300.
  expect(b.carryForward).toBeCloseTo(300, 2);
});

test('rollover_limit caps the carry-forward', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-cap', { amount: 700, rollover: 1, rolloverLimit: 100, categoryIds: ['food'] });
  // No April food spend → would otherwise carry $700, but cap holds at $100.
  await exec("DELETE FROM transactions WHERE category_id = 'food' AND date BETWEEN '2026-04-01' AND '2026-04-30'");
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'b-cap');
  expect(b.carryForward).toBe(100);
});

test('catches up multiple missed periods', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-catchup', { rollover: 0, startDate: '2026-01-01' });
  await rollBudgetsIfDue(exec, '2026-05-15');
  // Periods Jan, Feb, Mar, Apr should all be rolled; May is the current open period.
  const b = await readBudget(exec, 'b-catchup');
  expect(b.lastRolledPeriod).toBe('2026-04-01');
});

test('pending_amount activates at the boundary (rollover off)', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-pending', { rollover: 0 });
  await exec("UPDATE budgets SET pending_amount = 850 WHERE id = 'b-pending'");
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'b-pending');
  expect(b.amount).toBe(850);
  expect(b.pendingAmount).toBeNull();
  expect(b.lastRolledPeriod).toBe('2026-04-01');
});

test('pending_amount activates at the boundary (rollover on)', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-pending-roll', { amount: 700, rollover: 1, categoryIds: ['food'] });
  await exec("UPDATE budgets SET pending_amount = 850 WHERE id = 'b-pending-roll'");
  await exec("DELETE FROM transactions WHERE category_id = 'food' AND date BETWEEN '2026-04-01' AND '2026-04-30'");
  await exec(
    `INSERT INTO transactions (id,ledger_id,account_id,date,amount,amount_base,exchange_rate,description,category_id,status,currency,created_at,updated_at)
     VALUES ('t-apr-2','personal','chk','2026-04-10',-200,-200,1,'Groceries','food','confirmed','USD','2026-04-10','2026-04-10')`,
  );
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'b-pending-roll');
  // April used amount=700 to compute leftover = 700 - 200 = 500. Then
  // pending swaps in: amount becomes 850 for May.
  expect(b.amount).toBe(850);
  expect(b.carryForward).toBeCloseTo(500, 2);
});

test('one-shot budgets (is_recurring=0) are skipped entirely', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-oneshot', { isRecurring: 0, rollover: 1, startDate: '2026-04-01' });
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'b-oneshot');
  expect(b.lastRolledPeriod).toBeNull();
  expect(b.carryForward).toBe(0);
});

test('income type does not accrue carry_forward even with rollover=on', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-income', { type: 'income', rollover: 1, startDate: '2026-04-01', amount: 5000 });
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'b-income');
  // Rollover advances last_rolled_period but income type doesn't carry forward.
  expect(b.lastRolledPeriod).toBe('2026-04-01');
  expect(b.carryForward).toBe(0);
});

test('idempotent: a second call rolls 0', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-idem', { rollover: 0 });
  const first = await rollBudgetsIfDue(exec, '2026-05-15');
  expect(first.rolled).toBeGreaterThan(0);
  const second = await rollBudgetsIfDue(exec, '2026-05-15');
  expect(second.rolled).toBe(0);
});

test('past end_date budgets are skipped', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-ended');
  await exec("UPDATE budgets SET end_date = '2026-03-31' WHERE id = 'b-ended'");
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'b-ended');
  expect(b.lastRolledPeriod).toBeNull();
});

test('invalidateRollover resets state when an edit hits an already-rolled period', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-inv', { rollover: 1, categoryIds: ['food'] });
  await exec("UPDATE budgets SET last_rolled_period = '2026-04-01', carry_forward = 300 WHERE id = 'b-inv'");
  await invalidateRollover(exec, { categoryIds: ['food'], accountIds: [] }, '2026-04-10');
  const b = await readBudget(exec, 'b-inv');
  expect(b.lastRolledPeriod).toBeNull();
  expect(b.carryForward).toBe(0);
});

test('invalidateRollover ignores edits in periods not yet rolled', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-stable', { rollover: 1, categoryIds: ['food'] });
  await exec("UPDATE budgets SET last_rolled_period = '2026-04-01', carry_forward = 300 WHERE id = 'b-stable'");
  // A May edit (current open period, not yet rolled) doesn't invalidate.
  await invalidateRollover(exec, { categoryIds: ['food'], accountIds: [] }, '2026-05-10');
  const b = await readBudget(exec, 'b-stable');
  expect(b.lastRolledPeriod).toBe('2026-04-01');
  expect(b.carryForward).toBe(300);
});

test('invalidateRollover with empty category_ids treats budget as matching all', async () => {
  const exec = await seeded();
  // categoryIds = [] → budget matches every category
  await insertBudget(exec, 'b-allcats', { rollover: 1, categoryIds: [] });
  await exec("UPDATE budgets SET last_rolled_period = '2026-04-01', carry_forward = 50 WHERE id = 'b-allcats'");
  await invalidateRollover(exec, { categoryIds: ['something-random'], accountIds: [] }, '2026-04-10');
  const b = await readBudget(exec, 'b-allcats');
  expect(b.lastRolledPeriod).toBeNull();
});

test('invalidateRollover only touches budgets whose filters overlap the edit', async () => {
  const exec = await seeded();
  await insertBudget(exec, 'b-food', { rollover: 1, categoryIds: ['food'] });
  await insertBudget(exec, 'b-trans', { rollover: 1, categoryIds: ['trans'] });
  await exec("UPDATE budgets SET last_rolled_period = '2026-04-01', carry_forward = 50 WHERE id IN ('b-food','b-trans')");
  await invalidateRollover(exec, { categoryIds: ['food'], accountIds: [] }, '2026-04-10');
  const food = await readBudget(exec, 'b-food');
  const trans = await readBudget(exec, 'b-trans');
  expect(food.lastRolledPeriod).toBeNull();
  expect(trans.lastRolledPeriod).toBe('2026-04-01'); // untouched
});
