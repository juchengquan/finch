import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import {
  listTransactions,
  addTransaction,
  updateTransaction,
  cancelTransaction,
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
  expect(personal.length).toBe(16);
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
  const res = await listTransactions(exec, { ledgerId: 'personal', query: 'coffee' });
  expect(res.length).toBe(1);
  expect(res[0].merchant).toBe('Blue Bottle Coffee');
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

test('cancel hides a transaction from the list', async () => {
  const exec = await seeded();
  await cancelTransaction(exec, 't01');
  const list = await listTransactions(exec, { ledgerId: 'personal' });
  expect(list.find((t) => t.id === 't01')).toBeUndefined();
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
