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

async function readBudget(exec: Exec, id: string) {
  const [row] = await exec(
    'SELECT amount, carry_forward, pending_amount, last_rolled_period, frequency FROM budgets WHERE id = ?',
    [id],
  );
  return {
    amount: Number(row.amount),
    carryForward: Number(row.carry_forward ?? 0),
    pendingAmount: row.pending_amount == null ? null : Number(row.pending_amount),
    lastRolledPeriod: row.last_rolled_period == null ? null : String(row.last_rolled_period),
    frequency: String(row.frequency),
  };
}

test('rollBudgetsIfDue is a no-op when no period has closed since start_date', async () => {
  const exec = await seeded();
  // Set every monthly seeded budget's start_date to today so no boundary has passed.
  const today = '2026-05-15';
  await exec("UPDATE budgets SET start_date = ?, frequency = 'monthly'", [today]);
  const result = await rollBudgetsIfDue(exec, today);
  expect(result.rolled).toBe(0);
  const b = await readBudget(exec, 'bud-food');
  expect(b.lastRolledPeriod).toBeNull();
  expect(b.amount).toBe(700);
});

test('rollBudgetsIfDue rolls one closed period: rollover off → just advances marker', async () => {
  const exec = await seeded();
  // food budget: monthly, anchor Apr 1, today is May 15 → April just closed.
  // rollover off, so carry_forward stays 0 and pending_amount is null;
  // only last_rolled_period should advance.
  await exec("UPDATE budgets SET start_date = '2026-04-01', frequency = 'monthly', rollover = 0 WHERE id = 'bud-food'");
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'bud-food');
  expect(b.lastRolledPeriod).toBe('2026-04');
  expect(b.carryForward).toBe(0);
  expect(b.amount).toBe(700);
});

test('rollBudgetsIfDue rollover: leftover from April becomes carry_forward in May', async () => {
  const exec = await seeded();
  // food: monthly, anchor Apr 1, rollover on, no cap.
  await exec(
    "UPDATE budgets SET start_date = '2026-04-01', frequency = 'monthly', rollover = 1, rollover_limit = NULL WHERE id = 'bud-food'",
  );
  // Manually insert a controlled April food spend of $400.
  await exec(`DELETE FROM transactions WHERE category_id = 'food' AND date BETWEEN '2026-04-01' AND '2026-04-30'`);
  await exec(
    `INSERT INTO transactions (id,ledger_id,account_id,date,amount,amount_base,exchange_rate,exchange_rate_date,description,category_id,status,balance_after,currency,created_at)
     VALUES ('t-apr-1','personal','chk','2026-04-10',-400,-400,1,'2026-04-10','Groceries','food','confirmed',0,'USD','2026-04-10')`,
  );
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'bud-food');
  expect(b.lastRolledPeriod).toBe('2026-04');
  // Effective = 700 + 0 = 700; spent = 400; leftover = 300 → new carry-forward.
  expect(b.carryForward).toBeCloseTo(300, 2);
});

test('rollBudgetsIfDue catches up multiple missed periods', async () => {
  const exec = await seeded();
  await exec(
    "UPDATE budgets SET start_date = '2026-01-01', frequency = 'monthly', rollover = 0 WHERE id = 'bud-food'",
  );
  await rollBudgetsIfDue(exec, '2026-05-15');
  // From a NULL last_rolled, four periods close before May: Jan, Feb, Mar, Apr.
  const b = await readBudget(exec, 'bud-food');
  expect(b.lastRolledPeriod).toBe('2026-04');
});

test('rollover_limit caps the carry-forward', async () => {
  const exec = await seeded();
  await exec(
    "UPDATE budgets SET start_date = '2026-04-01', frequency = 'monthly', rollover = 1, rollover_limit = 100 WHERE id = 'bud-food'",
  );
  // No April food spend → entire $700 would roll, but the cap holds it at $100.
  await exec(`DELETE FROM transactions WHERE category_id = 'food' AND date BETWEEN '2026-04-01' AND '2026-04-30'`);
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'bud-food');
  expect(b.carryForward).toBe(100);
});

test('pending_amount activates at the boundary (even when rollover is off)', async () => {
  const exec = await seeded();
  await exec(
    "UPDATE budgets SET start_date = '2026-04-01', frequency = 'monthly', rollover = 0, pending_amount = 850 WHERE id = 'bud-food'",
  );
  await rollBudgetsIfDue(exec, '2026-05-15');
  const b = await readBudget(exec, 'bud-food');
  expect(b.amount).toBe(850);          // pending committed to active
  expect(b.pendingAmount).toBeNull();  // cleared
  expect(b.lastRolledPeriod).toBe('2026-04');
});

test('invalidateRollover resets state when an edit affects an already-rolled period', async () => {
  const exec = await seeded();
  // food already rolled through April with $300 carry.
  await exec(
    "UPDATE budgets SET start_date = '2026-04-01', frequency = 'monthly', last_rolled_period = '2026-04', carry_forward = 300 WHERE id = 'bud-food'",
  );
  // A backdated April food edit triggers invalidation.
  await invalidateRollover(exec, ['food'], '2026-04-10');
  const b = await readBudget(exec, 'bud-food');
  expect(b.lastRolledPeriod).toBeNull();
  expect(b.carryForward).toBe(0);
});

test('invalidateRollover ignores edits in periods that have not been rolled yet', async () => {
  const exec = await seeded();
  await exec(
    "UPDATE budgets SET start_date = '2026-04-01', frequency = 'monthly', last_rolled_period = '2026-04', carry_forward = 300 WHERE id = 'bud-food'",
  );
  // A May edit (the current open period) doesn't invalidate the April rollover.
  await invalidateRollover(exec, ['food'], '2026-05-10');
  const b = await readBudget(exec, 'bud-food');
  expect(b.lastRolledPeriod).toBe('2026-04');
  expect(b.carryForward).toBe(300);
});

test('rollBudgetsIfDue is idempotent: a second call rolls 0', async () => {
  const exec = await seeded();
  await exec(
    "UPDATE budgets SET start_date = '2026-04-01', frequency = 'monthly', rollover = 0 WHERE id = 'bud-food'",
  );
  const first = await rollBudgetsIfDue(exec, '2026-05-15');
  expect(first.rolled).toBeGreaterThan(0);
  const second = await rollBudgetsIfDue(exec, '2026-05-15');
  expect(second.rolled).toBe(0);
});
