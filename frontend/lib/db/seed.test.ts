import { test, expect } from 'bun:test';
import { seededDb } from '@/lib/db/test-utils';

const seeded = async () => (await seededDb()).exec;

const num = (rows: Record<string, unknown>[], key = 'n') => Number(rows[0]?.[key] ?? 0);

test('schema + seed loads the relational tables', async () => {
  const exec = await seeded();
  expect(num(await exec('SELECT count(*) AS n FROM ledgers'))).toBe(4);
  expect(num(await exec('SELECT count(*) AS n FROM accounts'))).toBe(6);
  expect(num(await exec('SELECT count(*) AS n FROM categories'))).toBe(19);
  expect(num(await exec('SELECT count(*) AS n FROM transactions'))).toBe(131);
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
  expect(personal).toBe(126);
  expect(family).toBe(5);
});

test('foreign seed rows derive their base from the rate table and lock the rate', async () => {
  const exec = await seeded();
  const [row] = await exec(
    "SELECT amount, amount_base, exchange_rate, currency FROM transactions WHERE id = 't-jpy-1'",
  );
  expect(Number(row.amount)).toBe(-3820); // native JPY
  expect(String(row.currency)).toBe('JPY');
  expect(Number(row.amount_base)).toBeCloseTo(-24.83, 2); // -3820 * 0.00650 (USD is the hub, rate(USD) = 1)
  expect(Number(row.exchange_rate)).toBeCloseTo(0.00650, 6);
});
