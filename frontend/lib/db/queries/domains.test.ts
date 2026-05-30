import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import { listAccounts, netWorth, accountBalanceSeries, updateAccount, createAccount, archiveAccount } from '@/lib/db/queries/accounts';
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

  // Display columns are seeded from data/accounts.json (no more override shim).
  expect(cc.last4).toBe('1009');
  expect(cc.color).toBe('#3a2d1f');

  await updateAccount(exec, 'cc', { name: 'Amex Platinum', last4: '9999', institution: 'American Express' });
  const updated = await listAccounts(exec, 'personal');
  const ccu = updated.find((a) => a.id === 'cc')!;
  expect(ccu.name).toBe('Amex Platinum');
  expect(ccu.last4).toBe('9999');
  expect(ccu.institution).toBe('American Express');
});

test('accounts: create, then archive removes from the active list', async () => {
  const exec = await seeded();
  await createAccount(exec, {
    id: 'acct-new', ledgerId: 'personal', name: 'Wise USD', type: 'cash',
    currency: 'USD', groupId: 'cash', openingBalance: 500, color: '#123456', last4: '0001',
  });
  let accts = await listAccounts(exec, 'personal');
  const created = accts.find((a) => a.id === 'acct-new')!;
  expect(created.name).toBe('Wise USD');
  expect(created.balance).toBeCloseTo(500, 2);

  await archiveAccount(exec, 'acct-new');
  accts = await listAccounts(exec, 'personal');
  expect(accts.find((a) => a.id === 'acct-new')).toBeUndefined();
});

test('categories: list + monthly spend', async () => {
  const exec = await seeded();
  expect((await listCategories(exec, 'personal')).length).toBe(8);
  const spend = await monthlyByCategory(exec, 'personal', '2026-05');
  const food = spend.find((c) => c.id === 'food')!;
  expect(food.spent).toBeGreaterThan(0);
  // Food spend should equal the sum of confirmed food expenses.
  expect(food.spent).toBeCloseTo(6.75 + 84.32 + 42.18 + 14.2 + 29.84, 2);

  // All-time map spans the full seed history — the prior-year `h*` rows
  // (groceries + dining) push the total well above the original Mar/Apr/May
  // sum; assert at least that minimum so it stays a meaningful regression test.
  const map = await categorySpend(exec, 'personal');
  expect(map.food).toBeGreaterThanOrEqual(6.75 + 84.32 + 42.18 + 14.2 + 29.84 + 132.8 + 96.5);
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

  const budgets = await budgetProgress(exec, 'personal', '2026-05-15');
  const food = budgets.find((b) => b.id === 'bud-food')!;
  expect(food.budget).toBe(700);
  expect(food.spent).toBeGreaterThan(0);
  expect(food.remaining).toBeCloseTo(food.budget - food.spent, 2);
});

test('budgetProgress derives each budget\'s own period from its frequency', async () => {
  const exec = await seeded();
  // Convert the seeded `food` budget to weekly so we can verify per-budget
  // period derivation drives the spend window.
  await exec("UPDATE budgets SET frequency = 'weekly', start_date = '2026-05-04' WHERE id = 'bud-food'");
  // Two confirmed food expenses in May, in different ISO weeks.
  await exec(
    `INSERT INTO transactions (id,ledger_id,account_id,date,amount,amount_base,exchange_rate,exchange_rate_date,description,category_id,status,balance_after,currency,created_at)
     VALUES ('t-w1','personal','chk','2026-05-04',-50,-50,1,'2026-05-04','Coffee','food','confirmed',0,'USD','2026-05-04'),
            ('t-w2','personal','chk','2026-05-13',-30,-30,1,'2026-05-13','Lunch','food','confirmed',0,'USD','2026-05-13')`,
  );
  // Today is 2026-05-13 (Wed of ISO W20). Weekly food budget's period
  // spans 2026-05-11 to 2026-05-17.
  const out = await budgetProgress(exec, 'personal', '2026-05-13');
  const food = out.find((b) => b.id === 'bud-food')!;
  expect(food.frequency).toBe('weekly');
  expect(food.period).toBe('2026-W20');
  expect(food.periodFrom).toBe('2026-05-11');
  expect(food.periodTo).toBe('2026-05-17');
  // Spent contains at least our inserted $30 (plus any seed txns the week
  // happens to cover) and is strictly less than the full month's food total
  // — proving the spend filter is scoped to the period, not the month.
  expect(food.spent).toBeGreaterThanOrEqual(30);
  expect(food.spent).toBeLessThan(6.75 + 84.32 + 42.18 + 14.2 + 29.84 + 30);
  // Other budgets stay monthly + carry their own period.
  const trans = out.find((b) => b.id === 'bud-trans')!;
  expect(trans.frequency).toBe('monthly');
  expect(trans.period).toBe('2026-05');
});
