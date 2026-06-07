import { test, expect } from 'bun:test';
import { seededDb } from '@/lib/db/test-utils';

const seeded = async () => (await seededDb()).exec;

const num = (rows: Record<string, unknown>[], key = 'n') => Number(rows[0]?.[key] ?? 0);

test('schema + seed loads the relational tables', async () => {
  const exec = await seeded();
  expect(num(await exec('SELECT count(*) AS n FROM ledgers'))).toBe(4);
  expect(num(await exec('SELECT count(*) AS n FROM accounts'))).toBe(6);
  // 19 user categories + 4 ledgers × 3 equity system categories (DOUBLE_ENTRY_PLAN §2.3)
  expect(num(await exec('SELECT count(*) AS n FROM categories'))).toBe(31);
  // Entries replaces the old transactions table (DOUBLE_ENTRY_PLAN). Seed has
  // 131 old tx rows; each becomes 1 entry (+ opening entries per account).
  // Account postings: 1 per non-opening entry + 1 per opening entry.
  // Just assert the entries count matches the seed tx row count (131).
  expect(num(await exec("SELECT count(*) AS n FROM entries WHERE kind != 'opening'"))).toBe(131);
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
  // §2: entries + postings replace transactions. Category legs have account_id IS NULL
  // and kind != 'equity'. Transfer entries have no category legs; expenses have positive.
  const rows = await exec(
    `SELECT c.id, c.name, SUM(p.amount_base) AS total
       FROM postings p
       JOIN entries e ON e.id = p.entry_id
       JOIN categories c ON c.id = p.category_id
      WHERE e.ledger_id = 'personal' AND e.date LIKE '2026-05%'
        AND p.account_id IS NULL AND c.kind != 'equity'
        AND e.kind NOT IN ('transfer') AND e.status = 'confirmed'
        AND p.amount_base > 0
      GROUP BY c.id ORDER BY total DESC`,
  );
  expect(rows.length).toBeGreaterThan(0);
  const food = rows.find((r) => r.id === 'food');
  expect(food).toBeTruthy();
  expect(Number(food!.total)).toBeGreaterThan(0);
});

test('ledger isolation: family transactions are scoped to the family ledger', async () => {
  const exec = await seeded();
  // §2: entries replaces transactions; exclude opening entries (1 per account).
  const personal = num(await exec("SELECT count(*) AS n FROM entries WHERE ledger_id = 'personal' AND kind != 'opening'"));
  const family = num(await exec("SELECT count(*) AS n FROM entries WHERE ledger_id = 'family' AND kind != 'opening'"));
  expect(personal).toBe(126);
  expect(family).toBe(5);
});

test('foreign seed rows derive their base from the rate table and lock the rate', async () => {
  const exec = await seeded();
  // §2: old tx id 't-jpy-1' preserved as entry id; account posting carries orig_amount/
  // orig_currency for the native display, amount/amount_base in the account's own
  // currency (USD here since 'cc' is a USD account). The exchange_rate is the locked rate.
  const [row] = await exec(
    "SELECT p.orig_amount, p.orig_currency, p.amount_base, p.exchange_rate FROM postings p WHERE p.entry_id = 't-jpy-1' AND p.account_id IS NOT NULL",
  );
  expect(Number(row.orig_amount)).toBe(-3820); // native JPY stored in orig_amount
  expect(String(row.orig_currency)).toBe('JPY');
  expect(Number(row.amount_base)).toBeCloseTo(-24.83, 2); // -3820 * 0.00650 (USD is the hub, rate(USD) = 1)
  expect(Number(row.exchange_rate)).toBeCloseTo(0.00650, 6);
});
