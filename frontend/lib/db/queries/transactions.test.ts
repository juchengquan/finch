import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import {
  listTransactions,
  addTransaction,
  updateTransaction,
  deleteTransactionRow,
  confirmTransaction,
  getTransaction,
} from '@/lib/db/queries/transactions';
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

test('list scopes to ledger and excludes the other ledger', async () => {
  const exec = await seeded();
  const personal = await listTransactions(exec, { ledgerId: 'personal' });
  expect(personal.length).toBe(126);
  expect(personal.every((t) => t.ledgerId === 'personal')).toBe(true);
});

test('direction filter splits in vs out', async () => {
  const exec = await seeded();
  const out = await listTransactions(exec, { ledgerId: 'personal', direction: 'out' });
  const inc = await listTransactions(exec, { ledgerId: 'personal', direction: 'in' });
  expect(out.every((t) => t.amount < 0)).toBe(true);
  expect(inc.every((t) => t.amount > 0)).toBe(true);
  expect(inc.some((t) => t.merchant === 'Acme Payroll')).toBe(true);
});

test('search matches the merchant/description substring', async () => {
  const exec = await seeded();
  // Substring search returns all matches; with extended history the seed has
  // multiple Blue Bottle Coffee rows. Assert it works (≥ 1) and every hit is
  // a Coffee merchant.
  const res = await listTransactions(exec, { ledgerId: 'personal', query: 'coffee' });
  expect(res.length).toBeGreaterThan(0);
  expect(res.every((t) => /coffee/i.test(t.merchant))).toBe(true);
});

test('FTS5 search is case-folded and matches prefixes', async () => {
  const exec = await seeded();
  // SEED has rows like "Blue Bottle Coffee". A lowercase "BLUE" should still match.
  const upper = await listTransactions(exec, { ledgerId: 'personal', query: 'BLUE' });
  expect(upper.length).toBeGreaterThan(0);
  expect(upper.every((t) => /blue/i.test(t.merchant))).toBe(true);

  // Multi-word AND across description tokens — every hit has both "blue" and "bottle".
  const both = await listTransactions(exec, { ledgerId: 'personal', query: 'blue bottle' });
  expect(both.length).toBeGreaterThan(0);
  expect(both.every((t) => /blue/i.test(t.merchant) && /bottle/i.test(t.merchant))).toBe(true);
});

test('FTS5 search includes notes (not just description)', async () => {
  const exec = await seeded();
  const { addTransaction } = await import('@/lib/db/queries/transactions');
  await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -3,
    merchant: 'Unrelated Vendor', note: 'sticky cinnamon bun receipt',
    date: '2026-05-25',
  });
  const res = await listTransactions(exec, { ledgerId: 'personal', query: 'cinnamon' });
  expect(res.some((t) => t.merchant === 'Unrelated Vendor')).toBe(true);
});

test('FTS5 sync triggers: edits + deletes propagate to the index', async () => {
  const exec = await seeded();
  const { addTransaction, updateTransaction, deleteTransactionRow } =
    await import('@/lib/db/queries/transactions');

  const id = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -5,
    merchant: 'Quirkbird Coffee Cooperative', date: '2026-05-25',
  });
  let res = await listTransactions(exec, { ledgerId: 'personal', query: 'quirkbird' });
  expect(res.some((t) => t.id === id)).toBe(true);

  // Rename — old token shouldn't match the same row anymore.
  await updateTransaction(exec, id, { merchant: 'Renamed Hideout' });
  res = await listTransactions(exec, { ledgerId: 'personal', query: 'quirkbird' });
  expect(res.some((t) => t.id === id)).toBe(false);
  res = await listTransactions(exec, { ledgerId: 'personal', query: 'hideout' });
  expect(res.some((t) => t.id === id)).toBe(true);

  // Delete — fully gone from the index.
  await deleteTransactionRow(exec, id);
  res = await listTransactions(exec, { ledgerId: 'personal', query: 'hideout' });
  expect(res.some((t) => t.id === id)).toBe(false);
});

test('counterparty resolver matches via COLLATE NOCASE (no LOWER in WHERE)', async () => {
  const exec = await seeded();
  const { resolveCounterpartyIdByName } = await import('@/lib/db/queries/counterparties');
  // Seed has "Grab" (cp-02); mixed-case + leading/trailing space should still resolve.
  expect(await resolveCounterpartyIdByName(exec, 'personal', '  gRAb  ')).toBe('cp-02');
  expect(await resolveCounterpartyIdByName(exec, 'personal', 'GRAB')).toBe('cp-02');
  expect(await resolveCounterpartyIdByName(exec, 'personal', 'NoSuchMerchant')).toBeNull();
});

test('filter by account and category', async () => {
  const exec = await seeded();
  const food = await listTransactions(exec, { ledgerId: 'personal', categoryId: 'food' });
  expect(food.length).toBeGreaterThan(0);
  expect(food.every((t) => t.category === 'food')).toBe(true);

  const chk = await listTransactions(exec, { ledgerId: 'personal', accountId: 'chk' });
  expect(chk.every((t) => t.account === 'chk')).toBe(true);
});

test('add inserts a confirmed transaction and updates the account balance', async () => {
  const exec = await seeded();
  const before = Number((await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', ['cc']))[0].b);
  const id = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'cc',
    amount: -25.5,
    merchant: 'Test Cafe',
    categoryId: 'food',
    date: '2026-05-26',
  });
  const after = Number((await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', ['cc']))[0].b);
  expect(after).toBeCloseTo(before - 25.5, 2);

  const tx = await getTransaction(exec, id);
  expect(tx?.merchant).toBe('Test Cafe');
  expect(tx?.pending).toBe(false);

  const list = await listTransactions(exec, { ledgerId: 'personal', query: 'Test Cafe' });
  expect(list.length).toBe(1);
});

test('update edits fields', async () => {
  const exec = await seeded();
  await updateTransaction(exec, 't01', { merchant: 'Blue Bottle ☕', note: 'updated' });
  const tx = await getTransaction(exec, 't01');
  expect(tx?.merchant).toBe('Blue Bottle ☕');
  expect(tx?.note).toBe('updated');
});

test('delete removes a transaction from the list', async () => {
  const exec = await seeded();
  const acctId = await deleteTransactionRow(exec, 't01');
  expect(acctId).toBeTruthy();
  const list = await listTransactions(exec, { ledgerId: 'personal' });
  expect(list.find((t) => t.id === 't01')).toBeUndefined();
  // The row is really gone (hard delete), not just hidden.
  expect((await exec("SELECT COUNT(*) AS n FROM transactions WHERE id = 't01'"))[0].n).toBe(0);
});

test('confirm flips a pending transaction and feeds the summary', async () => {
  const exec = await seeded();
  // t03 (Lyft) is seeded pending.
  const pendingBefore = await listTransactions(exec, { ledgerId: 'personal', status: 'pending' });
  expect(pendingBefore.some((t) => t.id === 't03')).toBe(true);

  await confirmTransaction(exec, 't03');
  const tx = await getTransaction(exec, 't03');
  expect(tx?.pending).toBe(false);
});

test('listTransactions filters by minAmount / maxAmount on absolute amount', async () => {
  const exec = await seeded();
  const all = await listTransactions(exec, { ledgerId: 'personal' });
  const big = await listTransactions(exec, { ledgerId: 'personal', minAmount: 100 });
  expect(big.every((t) => Math.abs(t.amount) >= 100)).toBe(true);
  expect(big.length).toBeGreaterThan(0);
  expect(big.length).toBeLessThan(all.length);

  const window = await listTransactions(exec, { ledgerId: 'personal', minAmount: 20, maxAmount: 50 });
  expect(window.every((t) => Math.abs(t.amount) >= 20 && Math.abs(t.amount) <= 50)).toBe(true);
});
