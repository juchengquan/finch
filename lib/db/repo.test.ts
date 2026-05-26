import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { initSchema, saveState, loadState, isEmpty, type Exec, type PersistState } from '@/lib/db/repo';

// The published types declare the init function as taking no arguments, but the
// runtime accepts a config object — re-type it to the slice we use.
const initSqlite = sqlite3InitModule as unknown as (
  opts?: { print?: () => void; printErr?: () => void },
) => ReturnType<typeof sqlite3InitModule>;

async function makeExec(): Promise<Exec> {
  const sqlite3 = await initSqlite({ print() {}, printErr() {} });
  const db = new sqlite3.oo1.DB(':memory:');
  return async (sql, bind) => {
    const rows: Record<string, SqlValue>[] = [];
    db.exec({ sql, bind: (bind ?? []) as SqlValue[], rowMode: 'object', resultRows: rows });
    return rows;
  };
}

const sample: PersistState = {
  transactions: [
    { id: 't01', merchant: 'Blue Bottle', category: 'food', amount: -6.75, account: 'cc', date: '2026-05-24', time: '08:14', note: 'Cortado', pending: false, recurring: false },
    { id: 't05', merchant: 'Acme Payroll', category: null, amount: 2900, account: 'chk', date: '2026-05-22', kind: 'income', pending: false },
  ],
  pending: [{ id: 'p1', merchant: 'Donki', amount: -82.4, currency: 'SGD', date: '2026-05-24', account: 'a', reason: 'verify', source: 'import' }],
  budgetOverrides: { food: 800 },
  verifiedExtra: ['cp-04'],
  aliasExtra: { 'cp-04': ['DDD', 'DON DONKI'] },
  recurring: [
    { id: 'rt-salary', name: 'Salary', type: 'income', amount: 5800, frequency: 'monthly', dayOfMonth: 25, account: 'a', autoPost: 0, nextRun: 'May 25', lastRun: 'Apr 25', splits: [{ account: 'a', pct: 60, abs: null, label: 'Daily' }] },
  ],
};

test('schema starts empty', async () => {
  const exec = await makeExec();
  await initSchema(exec);
  expect(await isEmpty(exec)).toBe(true);
});

test('state round-trips through SQLite', async () => {
  const exec = await makeExec();
  await initSchema(exec);
  await saveState(exec, sample);
  expect(await isEmpty(exec)).toBe(false);

  const loaded = await loadState(exec);
  expect(loaded.transactions).toHaveLength(2);
  const t01 = loaded.transactions.find((t) => t.id === 't01')!;
  expect(t01.amount).toBe(-6.75);
  expect(t01.pending).toBe(false);
  expect(loaded.transactions.find((t) => t.id === 't05')!.category).toBeNull();
  expect(loaded.pending[0].currency).toBe('SGD');
  expect(loaded.budgetOverrides.food).toBe(800);
  expect(loaded.verifiedExtra).toContain('cp-04');
  expect(loaded.aliasExtra['cp-04']).toEqual(['DDD', 'DON DONKI']);
  expect(loaded.recurring[0].splits?.[0].pct).toBe(60);
});

test('saveState replaces prior rows (no duplication)', async () => {
  const exec = await makeExec();
  await initSchema(exec);
  await saveState(exec, sample);
  await saveState(exec, { ...sample, transactions: [sample.transactions[0]] });
  const loaded = await loadState(exec);
  expect(loaded.transactions).toHaveLength(1);
});
