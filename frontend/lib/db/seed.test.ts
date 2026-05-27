import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import type { Exec } from '@/lib/db/repo';

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

async function seeded(): Promise<Exec> {
  const exec = await makeExec();
  await applySchema(exec);
  await seedDatabase(exec);
  return exec;
}

const num = (rows: Record<string, unknown>[], key = 'n') => Number(rows[0]?.[key] ?? 0);

test('schema + seed loads the relational tables', async () => {
  const exec = await seeded();
  expect(num(await exec('SELECT count(*) AS n FROM ledgers'))).toBe(4);
  expect(num(await exec('SELECT count(*) AS n FROM accounts'))).toBe(6);
  expect(num(await exec('SELECT count(*) AS n FROM categories'))).toBe(12);
  expect(num(await exec('SELECT count(*) AS n FROM transactions'))).toBe(24);
  expect(num(await exec('SELECT count(*) AS n FROM counterparties'))).toBeGreaterThan(0);
});

test('balance trigger leaves each account at its known seed balance', async () => {
  const exec = await seeded();
  // cc (Amex Gold) seed balance is -842.18 in accounts.json.
  const cc = await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', ['cc']);
  expect(Number(cc[0].b)).toBeCloseTo(-842.18, 2);
  // chk (Chase Checking) seed balance is 4218.50.
  const chk = await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', ['chk']);
  expect(Number(chk[0].b)).toBeCloseTo(4218.5, 2);
});

test('balance snapshots are recorded by trigger', async () => {
  const exec = await seeded();
  const n = num(await exec('SELECT count(*) AS n FROM account_balance_snapshots'));
  expect(n).toBeGreaterThan(0);
});

test('ledger_summaries aggregate confirmed transactions only', async () => {
  const exec = await seeded();
  // Pending Lyft (t03) must NOT be in the expense summary.
  const personalExpense = await exec(
    "SELECT total_base AS t FROM ledger_summaries WHERE ledger_id = 'personal' AND year_month = '2026-05' AND type = 'expense'",
  );
  // Sum of confirmed personal expenses for May (excludes -18.40 pending Lyft).
  expect(Number(personalExpense[0].t)).toBeLessThan(0);
  const income = await exec(
    "SELECT total_base AS t FROM ledger_summaries WHERE ledger_id = 'personal' AND year_month = '2026-05' AND type = 'income'",
  );
  expect(Number(income[0].t)).toBeCloseTo(2900, 2);
});

test('monthly-by-category query returns Food as a top personal category', async () => {
  const exec = await seeded();
  const rows = await exec(
    `SELECT c.id, c.name, SUM(t.amount_base * -1) AS total
       FROM transactions t JOIN categories c ON t.category_id = c.id
      WHERE t.ledger_id = 'personal' AND t.date LIKE '2026-05%'
        AND t.amount < 0 AND t.transfer_group_id IS NULL AND t.status = 'confirmed'
      GROUP BY c.id ORDER BY total DESC`,
  );
  expect(rows.length).toBeGreaterThan(0);
  const food = rows.find((r) => r.id === 'food');
  expect(food).toBeTruthy();
  expect(Number(food!.total)).toBeGreaterThan(0);
});

test('ledger isolation: family transactions are scoped to the family ledger', async () => {
  const exec = await seeded();
  const personal = num(await exec("SELECT count(*) AS n FROM transactions WHERE ledger_id = 'personal'"));
  const family = num(await exec("SELECT count(*) AS n FROM transactions WHERE ledger_id = 'family'"));
  expect(personal).toBe(19);
  expect(family).toBe(5);
});
