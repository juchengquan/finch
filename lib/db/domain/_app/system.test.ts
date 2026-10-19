import { test, expect } from 'bun:test';
import { rateToHub, convertToBase, HUB_CURRENCY } from '@/lib/db/domain/_app/system';
import { addTransaction } from '@/lib/db/domain/transactions/queries';
import { seededDb } from '@/lib/db/core/test-utils';
import type { Exec } from '@/lib/db/core/repo';
import { applyMutation } from '@/lib/db/mutate';
import { auditLedger } from '@/lib/db/core/entries';

async function seeded(): Promise<Exec> {
  const { exec } = await seededDb();
  return exec;
}

test('rateToHub: USD is the hub (always 1)', async () => {
  const exec = await seeded();
  expect(await rateToHub(exec, HUB_CURRENCY, '2026-05-24')).toBe(1);
});

test('rateToHub: returns the stored rate when one exists for the date', async () => {
  const exec = await seeded();
  expect(await rateToHub(exec, 'JPY', '2026-05-24')).toBeCloseTo(0.00650, 6);
  expect(await rateToHub(exec, 'SGD', '2026-05-24')).toBeCloseTo(0.74570, 6);
});

test('rateToHub: nearest on-or-before when the exact date is missing', async () => {
  const exec = await seeded();
  // 2026-05-25 has no row → returns the 2026-05-24 row.
  expect(await rateToHub(exec, 'JPY', '2026-05-25')).toBeCloseTo(0.00650, 6);
});

test('rateToHub: falls forward to the earliest stored rate for old backdates', async () => {
  const exec = await seeded();
  // Seed dates start at 2026-05-13. Asking for 2024-01-01 misses the on-or-before
  // window; we fall forward to the earliest stored rate (the 2026-05-13 row).
  expect(await rateToHub(exec, 'JPY', '2024-01-01')).toBeCloseTo(0.00650, 6);
});

test('rateToHub: static fallback when the currency has no rows', async () => {
  const exec = await seeded();
  // GBP is not in the seed → static FALLBACK_USD_PER_UNIT['GBP'] = 1.266.
  expect(await rateToHub(exec, 'GBP', '2026-05-24')).toBeCloseTo(1.266, 4);
});

test('convertToBase: same currency is identity', async () => {
  const exec = await seeded();
  expect(await convertToBase(exec, -42, 'USD', 'USD', '2026-05-24')).toEqual({ amountBase: -42, rate: 1 });
});

test('convertToBase: JPY → USD uses the stored rate directly', async () => {
  const exec = await seeded();
  const c = await convertToBase(exec, 1000, 'JPY', 'USD', '2026-05-24');
  expect(c.rate).toBeCloseTo(0.00650, 6);
  expect(c.amountBase).toBeCloseTo(6.5, 2);
});

test('convertToBase: JPY → SGD pivots through USD', async () => {
  const exec = await seeded();
  const c = await convertToBase(exec, 1000, 'JPY', 'SGD', '2026-05-24');
  // rate = rate(JPY) / rate(SGD) = 0.00650 / 0.74570 ≈ 0.008717
  expect(c.rate).toBeCloseTo(0.00650 / 0.74570, 6);
  expect(c.amountBase).toBeCloseTo((1000 * 0.00650) / 0.74570, 2);
});

test('addTransaction converts a foreign amount and locks the rate', async () => {
  const exec = await seeded();
  // cc is a USD account (personal ledger). Enter a JPY purchase.
  const id = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'cc',
    amount: -3820,
    currency: 'JPY',
    merchant: 'Yodobashi',
    date: '2026-05-24',
  });
  // §2: query via entries + postings instead of transactions.
  // Foreign-currency addTransaction stores orig_amount/orig_currency; amount is the
  // account-native (USD) amount; amount_base is ledger-base (USD == account-native here).
  // exchange_rate = account-ccy → ledger-base rate (1.0 for USD→USD). The effective
  // JPY→USD rate = |amount_base / orig_amount|.
  const [row] = await exec(
    'SELECT p.orig_amount, p.orig_currency, p.amount, p.amount_base FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL',
    [id],
  );
  expect(Number(row.orig_amount)).toBe(-3820);
  expect(String(row.orig_currency)).toBe('JPY');
  // JPY → USD direct: rate = rate(JPY) / rate(USD) = 0.00650 / 1.
  expect(Number(row.amount_base)).toBeCloseTo(-3820 * 0.00650, 2);
  // The effective rate locked at the date (derivable from orig/base amounts).
  const effectiveRate = Math.abs(Number(row.amount_base)) / Math.abs(Number(row.orig_amount));
  expect(effectiveRate).toBeCloseTo(0.00650, 6);
});

test('a conversion saves no copy of the rate it used', async () => {
  const exec = await seeded();
  const before = await exec('SELECT * FROM exchange_rates ORDER BY date, currency');
  // 2024-01-01 predates the seed range (falls forward to the earliest JPY row);
  // GBP has no rows (static fallback 1.266). Neither used to be pinned for nothing.
  expect(await rateToHub(exec, 'JPY', '2024-01-01')).toBeCloseTo(0.0065, 6);
  expect(await rateToHub(exec, 'GBP', '2026-05-24')).toBeCloseTo(1.266, 4);
  await convertToBase(exec, 1000, 'JPY', 'SGD', '2024-01-01');
  await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'cc', amount: -10, currency: 'GBP', merchant: 'London', date: '2026-05-24',
  });
  expect(await exec('SELECT * FROM exchange_rates ORDER BY date, currency')).toEqual(before);
  expect(await exec("SELECT * FROM exchange_rates WHERE source = 'derived'")).toEqual([]);
});

test('rateToHub skips a derived copy, on the date and before it', async () => {
  const exec = await seeded();
  await exec("INSERT INTO exchange_rates (date, currency, rate, source) VALUES ('2026-05-25', 'JPY', 0.0099, 'derived')");
  expect(await rateToHub(exec, 'JPY', '2026-05-25')).toBeCloseTo(0.0065, 6);
  expect(await rateToHub(exec, 'JPY', '2026-05-26')).toBeCloseTo(0.0065, 6);
  // …and a copy is no rate at all: GBP with only a derived row takes the fallback.
  await exec("INSERT INTO exchange_rates (date, currency, rate, source) VALUES ('2026-05-01', 'GBP', 9, 'derived')");
  expect(await rateToHub(exec, 'GBP', '2026-05-24')).toBeCloseTo(1.266, 4);
});

// ─── No rate for the pair: refuse, never 1:1 ─────────────────────────────────

const krwAccount = (exec: Exec) => exec(
  "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES ('krw','personal','Seoul','cash','KRW',0,99,1,1,datetime('now'),datetime('now'))",
);

test('rateToHub: null (and nothing pinned) for a currency with no rows and no fallback', async () => {
  const exec = await seeded();
  expect(await rateToHub(exec, 'KRW', '2026-05-24')).toBeNull();
  expect(await exec("SELECT * FROM exchange_rates WHERE currency = 'KRW'")).toEqual([]);
});

test('convertToBase: refuses a pair with no rate, naming it — never 1:1', async () => {
  const exec = await seeded();
  const err = await convertToBase(exec, -50000, 'KRW', 'USD', '2026-05-24').catch((e) => e);
  expect(err.code).toBe('error.fx.noRate');
  expect(err.params).toEqual({ from: 'KRW', to: 'USD', currency: 'KRW' });
  // The base side too, and a refusal pins nothing for the side that DID resolve.
  const err2 = await convertToBase(exec, 1000, 'JPY', 'KRW', '2024-01-01').catch((e) => e);
  expect(err2.params).toEqual({ from: 'JPY', to: 'KRW', currency: 'KRW' });
  expect(await exec("SELECT * FROM exchange_rates WHERE date = '2024-01-01'")).toEqual([]);
});

test('addTransaction on an unrated account is refused; once a rate exists it is used', async () => {
  const exec = await seeded();
  await krwAccount(exec);
  const add = () => addTransaction(exec, {
    ledgerId: 'personal', accountId: 'krw', amount: -50000, merchant: 'Seoul', date: '2026-05-24',
  });
  expect((await add().catch((e) => e)).code).toBe('error.fx.noRate');
  // A real rate dated BEFORE the refused attempt — the old 1.0 pin would shadow it.
  await exec("INSERT INTO exchange_rates (date, currency, rate) VALUES ('2026-05-01', 'KRW', 0.00072)");
  const id = await add();
  const [row] = await exec('SELECT amount_base FROM postings WHERE entry_id = ? AND account_id IS NOT NULL', [id]);
  expect(Number(row.amount_base)).toBeCloseTo(-36, 2);
});

// ─── A rate the user set or fetched always outranks a copy ───────────────────

const setRate = (exec: Exec, date: string, rate: number, source = 'manual') =>
  applyMutation(exec, 'setExchangeRate', { date, currency: 'KRW', rate, source });
const spendKrw = (exec: Exec, amount: number, date: string) => addTransaction(exec, {
  ledgerId: 'personal', accountId: 'krw', amount, merchant: 'Seoul', date,
});
async function krwBase(exec: Exec, amount: number, date: string): Promise<number> {
  const [row] = await exec(
    "SELECT p.amount_base FROM postings p JOIN entries e ON e.id = p.entry_id WHERE p.account_id = 'krw' AND p.amount = ? AND e.date = ?",
    [amount, date],
  );
  return Number(row.amount_base);
}
const krwRates = (exec: Exec) => exec("SELECT * FROM exchange_rates WHERE currency = 'KRW'");

test('F1: a corrected rate is what later entries use', async () => {
  const exec = await seeded();
  await krwAccount(exec);
  await setRate(exec, '2026-05-01', 0.0073);              // mistyped
  await spendKrw(exec, -50000, '2026-05-10');
  expect(await krwBase(exec, -50000, '2026-05-10')).toBeCloseTo(-365, 2);
  expect(await krwRates(exec)).toHaveLength(1);           // no copy saved
  await setRate(exec, '2026-05-01', 0.00073);             // corrected
  await spendKrw(exec, -50001, '2026-05-10');
  await spendKrw(exec, -50000, '2026-05-12');
  expect(await krwBase(exec, -50001, '2026-05-10')).toBeCloseTo(-36.5, 2);
  expect(await krwBase(exec, -50000, '2026-05-12')).toBeCloseTo(-36.5, 2);
});

test('F1: a backdated rate is what later entries use', async () => {
  const exec = await seeded();
  await krwAccount(exec);
  await setRate(exec, '2026-05-01', 0.00072, 'ECB');
  await spendKrw(exec, -50000, '2026-05-10');
  await setRate(exec, '2026-05-05', 0.0008);              // backdated, by hand
  await spendKrw(exec, -50001, '2026-05-10');
  await spendKrw(exec, -50000, '2026-05-12');
  expect(await krwBase(exec, -50001, '2026-05-10')).toBeCloseTo(-40, 2);
  expect(await krwBase(exec, -50000, '2026-05-12')).toBeCloseTo(-40, 2);
  expect(await krwBase(exec, -50000, '2026-05-10')).toBeCloseTo(-36, 2); // booked before it
});

test('W1: a leftover 1:1 derived rate does not book new money', async () => {
  const exec = await seeded();
  await krwAccount(exec);
  await exec("INSERT INTO exchange_rates (date, currency, rate, source) VALUES ('2026-05-01', 'KRW', 1, 'derived')");
  for (const date of ['2026-05-09', '2026-05-01']) {
    const err = await spendKrw(exec, -10000, date).catch((e) => e);
    expect(err.code).toBe('error.fx.noRate');
    expect(err.params).toEqual({ from: 'KRW', to: 'USD', currency: 'KRW' });
  }
  expect(await krwRates(exec)).toHaveLength(1);
  await setRate(exec, '2026-05-09', 0.00073);             // the "Enter a rate" path
  await spendKrw(exec, -10000, '2026-05-09');
  expect(await krwBase(exec, -10000, '2026-05-09')).toBeCloseTo(-7.3, 2);
});

test('an existing entry keeps its rate until an edit re-values it', async () => {
  const exec = await seeded();
  await krwAccount(exec);
  await setRate(exec, '2026-05-01', 0.0073);              // mistyped
  const id = await spendKrw(exec, -50000, '2026-05-10');
  await setRate(exec, '2026-05-01', 0.00073);             // corrected
  await applyMutation(exec, 'updateTransaction', { id, patch: { note: 'dinner' } });
  expect(await krwBase(exec, -50000, '2026-05-10')).toBeCloseTo(-365, 2);   // header edit: kept
  await applyMutation(exec, 'updateTransaction', { id, patch: { date: '2026-05-11' } });
  expect(await krwBase(exec, -50000, '2026-05-11')).toBeCloseTo(-36.5, 2);  // date edit: re-valued
  await applyMutation(exec, 'updateTransaction', { id, patch: { amount: -60000 } });
  expect(await krwBase(exec, -60000, '2026-05-11')).toBeCloseTo(-43.8, 2);
  expect(await krwRates(exec)).toHaveLength(1);
  expect(await auditLedger(exec, 'personal', { checkBalances: true })).toEqual([]);
});
