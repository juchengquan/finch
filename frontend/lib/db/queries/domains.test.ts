import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import { listAccounts, netWorth, accountBalanceSeries, setAccountDetails } from '@/lib/db/queries/accounts';
import { listCategories, monthlyByCategory, categorySpend } from '@/lib/db/queries/categories';
import { listCounterparties, searchCounterparties, verifyCounterparty, addAlias } from '@/lib/db/queries/counterparties';
import { monthlyCashFlow, budgetProgress } from '@/lib/db/queries/reports';
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
  return exec;
}

test('accounts: list, net worth, balance series, edit', async () => {
  const exec = await seeded();
  const accts = await listAccounts(exec, 'personal');
  expect(accts.length).toBe(4); // chk, sav, cc, inv
  const cc = accts.find((a) => a.id === 'cc')!;
  expect(cc.groupName).toBe('Credit Cards');
  expect(cc.includeInNetWorth).toBe(0); // credit group excluded by default

  // Net worth excludes the credit card group (-842.18), so it's assets only.
  const nw = await netWorth(exec, 'personal');
  expect(nw).toBeCloseTo(4218.5 + 8120 + 21430, 2);

  const series = await accountBalanceSeries(exec, 'cc');
  expect(series.length).toBeGreaterThan(0);

  await setAccountDetails(exec, 'cc', { name: 'Amex Platinum' });
  const updated = await listAccounts(exec, 'personal');
  expect(updated.find((a) => a.id === 'cc')!.name).toBe('Amex Platinum');
});

test('categories: list + monthly spend', async () => {
  const exec = await seeded();
  expect((await listCategories(exec, 'personal')).length).toBe(8);
  const spend = await monthlyByCategory(exec, 'personal', '2026-05');
  const food = spend.find((c) => c.id === 'food')!;
  expect(food.spent).toBeGreaterThan(0);
  // Food spend should equal the sum of confirmed food expenses.
  expect(food.spent).toBeCloseTo(6.75 + 84.32 + 42.18 + 14.2 + 29.84, 2);

  // All-time map matches the same figure for this seed (all txns are in May).
  const map = await categorySpend(exec, 'personal');
  expect(map.food).toBeCloseTo(6.75 + 84.32 + 42.18 + 14.2 + 29.84, 2);
});

test('counterparties: list, search, verify, alias', async () => {
  const exec = await seeded();
  expect((await listCounterparties(exec, 'personal')).length).toBeGreaterThan(0);

  const grab = await searchCounterparties(exec, 'personal', 'GRAB');
  expect(grab.some((c) => c.name === 'Grab')).toBe(true);

  const donki = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(donki.verified).toBe(false);
  await verifyCounterparty(exec, 'cp-04');
  await addAlias(exec, 'cp-04', 'DONKI JURONG');
  const after = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(after.verified).toBe(true);
  expect(after.aliases).toContain('DONKI JURONG');
});

test('reports: cash flow + budget progress', async () => {
  const exec = await seeded();
  const cf = await monthlyCashFlow(exec, 'personal', '2026-05');
  expect(cf.income).toBeCloseTo(2900, 2);
  expect(cf.expense).toBeLessThan(0);
  expect(cf.net).toBeCloseTo(cf.income + cf.expense, 2);

  const budgets = await budgetProgress(exec, 'personal', '2026-05');
  const food = budgets.find((b) => b.id === 'bud-food')!;
  expect(food.budget).toBe(700);
  expect(food.spent).toBeGreaterThan(0);
  expect(food.remaining).toBeCloseTo(food.budget - food.spent, 2);
});
