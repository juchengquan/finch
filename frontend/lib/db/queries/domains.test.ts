import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import { listAccounts, netWorth, updateAccount, createAccount, archiveAccount } from '@/lib/db/queries/accounts';
import { listCategories, monthlyByCategory, categorySpend } from '@/lib/db/queries/categories';
import { listCounterparties, searchCounterparties, verifyCounterparty } from '@/lib/db/queries/counterparties';
import { monthlyCashFlow } from '@/lib/db/queries/reports';
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
  expect(cc.includeInNetWorth).toBe(0); // credit_card type excluded by default

  // Net worth excludes the credit card group (-842.18), so it's assets only.
  const nw = await netWorth(exec, 'personal');
  expect(nw).toBeCloseTo(4218.5 + 8120 + 21430, 2);

  // Display columns are seeded from data/accounts.json.
  expect(cc.name).toBe('Amex Gold');
  expect(cc.color).toBe('#3a2d1f');

  await updateAccount(exec, 'cc', { name: 'Amex Platinum' });
  const updated = await listAccounts(exec, 'personal');
  const ccu = updated.find((a) => a.id === 'cc')!;
  expect(ccu.name).toBe('Amex Platinum');
});

test('accounts: create, then archive removes from the active list', async () => {
  const exec = await seeded();
  await createAccount(exec, {
    id: 'acct-new', ledgerId: 'personal', name: 'Wise USD', type: 'cash',
    currency: 'USD', groupId: 'cash', openingBalance: 500, color: '#123456',
  });
  let accts = await listAccounts(exec, 'personal');
  const created = accts.find((a) => a.id === 'acct-new')!;
  expect(created.name).toBe('Wise USD');
  expect(created.balance).toBeCloseTo(500, 2);

  await archiveAccount(exec, 'acct-new');
  accts = await listAccounts(exec, 'personal');
  expect(accts.find((a) => a.id === 'acct-new')).toBeUndefined();

  // archived_at is stamped so the audit trail survives the soft-delete.
  const [archived] = await exec("SELECT is_active, archived_at FROM accounts WHERE id = 'acct-new'");
  expect(Number(archived.is_active)).toBe(0);
  expect(archived.archived_at).not.toBeNull();
});

test('accounts: createAccount assigns an incrementing sort_order within the same group', async () => {
  const exec = await seeded();
  await createAccount(exec, {
    id: 'acct-a', ledgerId: 'personal', name: 'A', type: 'cash',
    currency: 'USD', groupId: 'cash', openingBalance: 0, color: null,
  });
  await createAccount(exec, {
    id: 'acct-b', ledgerId: 'personal', name: 'B', type: 'cash',
    currency: 'USD', groupId: 'cash', openingBalance: 0, color: null,
  });
  const accts = await listAccounts(exec, 'personal');
  const a = accts.find((x) => x.id === 'acct-a')!;
  const b = accts.find((x) => x.id === 'acct-b')!;
  expect(b.sortOrder).toBeGreaterThan(a.sortOrder);
});

test('categories: list + monthly spend', async () => {
  const exec = await seeded();
  expect((await listCategories(exec, 'personal')).length).toBe(15); // 8 top-level + 7 demo subcategories
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

test('categories: 2-level tree — parent_id wires children, build+rollup behave', async () => {
  const exec = await seeded();
  const { buildCategoryTree, rollupCategorySpend } = await import('@/lib/db/queries/categories');
  const cats = await listCategories(exec, 'personal');

  // Seeded demo children carry their parent id.
  const groceries = cats.find((c) => c.id === 'food-groceries')!;
  expect(groceries.parentId).toBe('food');
  const food = cats.find((c) => c.id === 'food')!;
  expect(food.parentId).toBeNull();

  // Tree groups children under their parent; childless parents come back with [].
  const tree = buildCategoryTree(cats);
  const foodNode = tree.find((n) => n.parent.id === 'food')!;
  expect(foodNode.children.map((c) => c.id).sort()).toEqual(
    ['food-coffee', 'food-groceries', 'food-restaurants'].sort(),
  );
  expect(tree.find((n) => n.parent.id === 'rent')!.children).toEqual([]);

  // rollupCategorySpend folds child totals into the parent bucket.
  const rolled = rollupCategorySpend({ food: 10, 'food-groceries': 30, 'food-coffee': 5 }, cats);
  expect(rolled.food).toBe(10 + 30 + 5);
  expect(rolled['food-groceries']).toBe(30); // children keep their own line too
});

test('createCategory rejects nesting under a row that already has a parent (no 3-level)', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  await expect(
    applyMutation(exec, 'createCategory', {
      ledgerId: 'personal', name: 'Espresso', parentId: 'food-coffee',
    }),
  ).rejects.toThrow(/two levels/i);
});

test('deleteCategory promotes children to top-level (ON DELETE SET NULL)', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  // 'food' has demo children. Delete it; the children should survive as top-level.
  await applyMutation(exec, 'deleteCategory', { id: 'food' });
  const after = await listCategories(exec, 'personal');
  const groceries = after.find((c) => c.id === 'food-groceries')!;
  expect(groceries).toBeTruthy();
  expect(groceries.parentId).toBeNull();
});

test('counterparties: list, search, verify, alias', async () => {
  const exec = await seeded();
  expect((await listCounterparties(exec, 'personal')).length).toBeGreaterThan(0);

  const grab = await searchCounterparties(exec, 'personal', 'GRAB');
  expect(grab.some((c) => c.name === 'Grab')).toBe(true);

  const donki = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(donki.verified).toBe(false);
  await verifyCounterparty(exec, 'cp-04');
  const after = (await listCounterparties(exec, 'personal')).find((c) => c.id === 'cp-04')!;
  expect(after.verified).toBe(true);
});

test('counterparty FK: addTransaction links exact name (case-insensitive), null on no match', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');

  const matched = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -10,
    merchant: 'grab', // lowercase — exists as 'Grab' (cp-02)
    date: '2026-05-25',
  });
  const [m] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [matched]);
  expect(String(m.counterparty_id)).toBe('cp-02');

  const unmatched = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -10,
    merchant: 'Random Shop That Has No Catalog Entry',
    date: '2026-05-25',
  });
  const [u] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [unmatched]);
  expect(u.counterparty_id).toBeNull();
});

test('counterparty FK: renaming a counterparty makes projectState surface the canonical name', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  const { applyMutation } = await import('@/lib/db/mutations');
  const { projectState } = await import('@/lib/db/state');

  // Insert a row that links to Grab (cp-02).
  await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -8,
    merchant: 'Grab', date: '2026-05-25',
  });

  // Rename the catalog entry; projected merchant should follow the new name
  // even though `transactions.description` is unchanged.
  await applyMutation(exec, 'updateCounterparty', { id: 'cp-02', patch: { name: 'Grab Mobility' } });
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.counterpartyId === 'cp-02')!;
  expect(tx).toBeTruthy();
  expect(tx.merchant).toBe('Grab Mobility');
});

test('counterparty FK: updateTransaction re-resolves when merchant text changes', async () => {
  const exec = await seeded();
  const { addTransaction, updateTransaction } = await import('@/lib/db/queries/transactions');

  // Start with a row linked to Grab (cp-02).
  const txId = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -8,
    merchant: 'Grab', date: '2026-05-25',
  });
  let [row] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.counterparty_id)).toBe('cp-02');

  // Rename merchant to a non-catalog string; link should drop to NULL.
  await updateTransaction(exec, txId, { merchant: 'Some One-off Vendor' });
  [row] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(row.counterparty_id).toBeNull();

  // Rename to a known catalog name; link should re-establish.
  await updateTransaction(exec, txId, { merchant: 'Apple' }); // cp-05
  [row] = await exec('SELECT counterparty_id FROM transactions WHERE id = ?', [txId]);
  expect(String(row.counterparty_id)).toBe('cp-05');
});

test('counterparty FK: deleting a counterparty leaves linked transactions intact (SET NULL)', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  const { applyMutation } = await import('@/lib/db/mutations');

  const txId = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -8,
    merchant: 'Grab', date: '2026-05-25',
  });
  await applyMutation(exec, 'deleteCounterparty', { id: 'cp-02' });
  const [row] = await exec('SELECT counterparty_id, description FROM transactions WHERE id = ?', [txId]);
  expect(row.counterparty_id).toBeNull();
  expect(String(row.description)).toBe('Grab');
});

test('changeLedgerBase: rewrites amount_base under the new base using each txn date', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  const { convertToBase } = await import('@/lib/db/queries/rates');
  const { listLedgers } = await import('@/lib/db/queries/ledgers');

  // The personal ledger seeds with USD base. Switch to SGD and verify each
  // transaction's amount_base now equals convertToBase(native, currency, SGD, date).
  const beforeLedger = (await listLedgers(exec)).find((l) => l.id === 'personal')!;
  expect(beforeLedger.base).toBe('USD');

  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'SGD' });

  const afterLedger = (await listLedgers(exec)).find((l) => l.id === 'personal')!;
  expect(afterLedger.base).toBe('SGD');

  // Spot-check the foreign JPY seed row (t-jpy-1, native ¥-3820 on 2026-05-13).
  const [jpy] = await exec("SELECT amount, currency, date, amount_base, exchange_rate FROM transactions WHERE id = 't-jpy-1'");
  const expected = await convertToBase(exec, Number(jpy.amount), String(jpy.currency), 'SGD', String(jpy.date));
  expect(Number(jpy.amount_base)).toBeCloseTo(expected.amountBase, 2);
  expect(Number(jpy.exchange_rate)).toBeCloseTo(expected.rate, 6);

  // Spot-check a same-currency row (any USD row) — rate should be 1, base = native.
  const [usd] = await exec("SELECT id, amount, amount_base, exchange_rate FROM transactions WHERE ledger_id = 'personal' AND currency = 'SGD' LIMIT 1");
  if (usd) {
    expect(Number(usd.amount_base)).toBeCloseTo(Number(usd.amount), 2);
    expect(Number(usd.exchange_rate)).toBeCloseTo(1, 6);
  }
});

test('changeLedgerBase: same-base call is a no-op', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  const before = await exec("SELECT id, amount_base, exchange_rate FROM transactions WHERE ledger_id = 'personal' ORDER BY id");
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'USD' });
  const after = await exec("SELECT id, amount_base, exchange_rate FROM transactions WHERE ledger_id = 'personal' ORDER BY id");
  expect(JSON.stringify(after)).toBe(JSON.stringify(before));
});

test('changeLedgerBase: rejects malformed currency codes', async () => {
  const exec = await seeded();
  const { applyMutation } = await import('@/lib/db/mutations');
  await expect(applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'usd' }))
    .resolves.toBeUndefined(); // case-insensitive: lowercased input is accepted (validator uppercases)
  await expect(applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'US' }))
    .rejects.toThrow(/3-letter/);
  await expect(applyMutation(exec, 'changeLedgerBase', { ledgerId: 'personal', newBase: 'usd1' }))
    .rejects.toThrow(/3-letter/);
});

test('reports: monthly cash flow', async () => {
  const exec = await seeded();
  const cf = await monthlyCashFlow(exec, 'personal', '2026-05');
  expect(cf.income).toBeCloseTo(2900, 2);
  expect(cf.expense).toBeLessThan(0);
  expect(cf.net).toBeCloseTo(cf.income + cf.expense, 2);
});
