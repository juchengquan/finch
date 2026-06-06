import { test, expect } from 'bun:test';
import { rateToHub, convertToBase, HUB_CURRENCY } from '@/lib/db/queries/rates';
import { addTransaction } from '@/lib/db/queries/transactions';
import { seededDb } from '@/lib/db/test-utils';
import type { Exec } from '@/lib/db/repo';

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
  const [row] = await exec('SELECT amount, amount_base, exchange_rate, currency FROM transactions WHERE id = ?', [id]);
  expect(Number(row.amount)).toBe(-3820);
  expect(String(row.currency)).toBe('JPY');
  // JPY → USD direct: rate = rate(JPY) / rate(USD) = 0.00650 / 1.
  expect(Number(row.amount_base)).toBeCloseTo(-3820 * 0.00650, 2);
  expect(Number(row.exchange_rate)).toBeCloseTo(0.00650, 6);
});

test('write-through: a resolved fallback rate is pinned under the requested date', async () => {
  const exec = await seeded();
  // 2024-01-01 predates the seed range (2026-05-13 →) — resolution falls
  // forward to the earliest stored JPY rate (0.00650) and must pin it.
  const rate = await rateToHub(exec, 'JPY', '2024-01-01');
  expect(rate).toBeCloseTo(0.0065, 6);
  const [pinned] = await exec(
    "SELECT rate, source FROM exchange_rates WHERE currency = 'JPY' AND date = '2024-01-01'",
  );
  expect(Number(pinned.rate)).toBeCloseTo(0.0065, 6);
  expect(String(pinned.source)).toBe('derived');
});

test('write-through: the pinned rate keeps old-date conversions stable when neighbors change', async () => {
  const exec = await seeded();
  const first = await convertToBase(exec, 1000, 'JPY', 'SGD', '2024-01-01');
  // Rewrite the rates the original resolution fell forward to. Without the
  // pin, re-running the same conversion would now produce a different figure.
  await exec("UPDATE exchange_rates SET rate = 0.0099 WHERE currency = 'JPY' AND date >= '2026-01-01'");
  const second = await convertToBase(exec, 1000, 'JPY', 'SGD', '2024-01-01');
  expect(second.rate).toBeCloseTo(first.rate, 6);
  expect(second.amountBase).toBeCloseTo(first.amountBase, 2);
});

test('write-through: never clobbers an exact user-set rate', async () => {
  const exec = await seeded();
  // Exact-date hit returns the stored row untouched (no 'derived' overwrite).
  expect(await rateToHub(exec, 'JPY', '2026-05-24')).toBeCloseTo(0.0065, 6);
  const [row] = await exec(
    "SELECT rate, source FROM exchange_rates WHERE currency = 'JPY' AND date = '2026-05-24'",
  );
  expect(String(row.source)).not.toBe('derived');
});

test('write-through: static fallback for an unknown currency is pinned too', async () => {
  const exec = await seeded();
  // GBP has no seed rows → static FALLBACK_USD_PER_UNIT['GBP'] = 1.266, pinned.
  expect(await rateToHub(exec, 'GBP', '2026-05-24')).toBeCloseTo(1.266, 4);
  const [pinned] = await exec(
    "SELECT rate, source FROM exchange_rates WHERE currency = 'GBP' AND date = '2026-05-24'",
  );
  expect(Number(pinned.rate)).toBeCloseTo(1.266, 4);
  expect(String(pinned.source)).toBe('derived');
});
