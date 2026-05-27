import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import { rateToSgd, convertToBase } from '@/lib/db/queries/rates';
import { addTransaction } from '@/lib/db/queries/transactions';
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

test('rateToSgd: SGD is 1, table rate resolves, nearest-on-or-before, fallback', async () => {
  const exec = await seeded();
  expect(await rateToSgd(exec, 'SGD', '2026-05-24')).toBe(1);
  expect(await rateToSgd(exec, 'JPY', '2026-05-24')).toBeCloseTo(0.00872, 6);
  // 2026-05-25 has no row → nearest on-or-before is the 05-24 row.
  expect(await rateToSgd(exec, 'JPY', '2026-05-25')).toBeCloseTo(0.00872, 6);
  // GBP has no rows at all → static fallback (1.35 / 0.79).
  expect(await rateToSgd(exec, 'GBP', '2026-05-24')).toBeCloseTo(1.35 / 0.79, 4);
});

test('convertToBase: same currency is identity', async () => {
  const exec = await seeded();
  expect(await convertToBase(exec, -42, 'USD', 'USD', '2026-05-24')).toEqual({ amountBase: -42, rate: 1 });
});

test('convertToBase: JPY → SGD uses rate_to_sgd directly', async () => {
  const exec = await seeded();
  const c = await convertToBase(exec, 1000, 'JPY', 'SGD', '2026-05-24');
  expect(c.rate).toBeCloseTo(0.00872, 6);
  expect(c.amountBase).toBeCloseTo(8.72, 2);
});

test('convertToBase: JPY → USD pivots through SGD', async () => {
  const exec = await seeded();
  const c = await convertToBase(exec, 1000, 'JPY', 'USD', '2026-05-24');
  expect(c.rate).toBeCloseTo(0.00872 / 1.3412, 6);
  expect(c.amountBase).toBeCloseTo((1000 * 0.00872) / 1.3412, 2);
});

test('addTransaction converts a foreign amount to the account base and locks the rate', async () => {
  const exec = await seeded();
  // cc is a USD account (personal base). Enter a JPY purchase.
  const id = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'cc',
    amount: -3820,
    currency: 'JPY',
    merchant: 'Yodobashi',
    date: '2026-05-24',
  });
  const [row] = await exec('SELECT amount, amount_base, exchange_rate, currency FROM transactions WHERE id = ?', [id]);
  expect(Number(row.amount)).toBe(-3820);
  expect(String(row.currency)).toBe('JPY');
  expect(Number(row.amount_base)).toBeCloseTo((-3820 * 0.00872) / 1.3412, 2);
  expect(Number(row.exchange_rate)).toBeCloseTo(0.00872 / 1.3412, 6);
});
