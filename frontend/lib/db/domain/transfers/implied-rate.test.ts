// A cross-currency transfer where the user typed BOTH amounts states exactly what
// moved, so the two amounts imply the rate. When one side has no exchange rate it
// is valued at the other side's base amount instead of refusing the write — the
// entry balances with no FX leg, and the implied rate is never saved as a rate.
// Only when NEITHER side can be valued in base is it still `error.fx.noRate`.
// Mirrors FinchCore's TransferImpliedRateTests.

import { test, expect } from 'bun:test';
import { freshDb } from '@/lib/db/core/test-utils';
import { applyMutation } from '@/lib/db/mutate';
import type { Exec } from '@/lib/db/core/repo';

/** A USD ledger (unless `base` says otherwise) with a1 in `fromCcy` and a2 in
 *  `toCcy`. No exchange rates at all: KRW and VND have no static fallback. */
async function seeded(base = 'USD', fromCcy = 'USD', toCcy = 'KRW'): Promise<Exec> {
  const { exec } = await freshDb();
  await exec("INSERT INTO ledgers (id,name,base_currency,is_default,created_at,updated_at) VALUES ('l1','L',?,1,datetime('now'),datetime('now'))", [base]);
  for (const [id, name, ccy, order] of [['a1', 'Checking', fromCcy, 0], ['a2', 'Seoul', toCcy, 1]] as const) {
    await exec(
      "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,sort_order,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,'l1',?,'cash',?,0,?,1,1,datetime('now'),datetime('now'))",
      [id, name, ccy, order],
    );
  }
  return exec;
}

const transfer = (exec: Exec, fromAmount = 100, toAmount: number | null = 137000) =>
  applyMutation(exec, 'createTransfer', {
    fromAccountId: 'a1', toAccountId: 'a2', fromAmount, date: '2026-05-16',
    ...(toAmount != null ? { toAmount } : {}),
  });

async function booked(exec: Exec) {
  const [from] = await exec("SELECT amount, amount_base, exchange_rate FROM postings WHERE account_id = 'a1'");
  const [to] = await exec("SELECT amount, amount_base, exchange_rate FROM postings WHERE account_id = 'a2'");
  const [fx] = await exec('SELECT COUNT(*) AS n FROM postings WHERE account_id IS NULL');
  const [rates] = await exec('SELECT COUNT(*) AS n FROM exchange_rates');
  const [sum] = await exec('SELECT ROUND(SUM(amount_base), 2) AS s FROM postings');
  return {
    fromBase: Number(from.amount_base), to: { amount: Number(to.amount), base: Number(to.amount_base), rate: Number(to.exchange_rate) },
    fxLegs: Number(fx.n), rates: Number(rates.n), sum: Number(sum.s),
  };
}

const noRate = async (p: Promise<unknown>) => expect(((await p.catch((e) => e)) as { code?: string }).code).toBe('error.fx.noRate');

test('both amounts typed, unrated receiving side: books, balances, no FX leg, no rate saved', async () => {
  const exec = await seeded();
  await transfer(exec);
  const b = await booked(exec);
  expect(b.fromBase).toBeCloseTo(-100, 3);
  expect(b.to.amount).toBeCloseTo(137000, 3);
  expect(b.to.base).toBeCloseTo(100, 3);
  expect(b.to.rate).toBeCloseTo(0.00073, 9); // 100 / 137,000, as applied
  expect(b.sum).toBeCloseTo(0, 3);
  expect(b.fxLegs).toBe(0);
  expect(b.rates).toBe(0);
  const [acct] = await exec("SELECT current_balance FROM accounts WHERE id = 'a2'");
  expect(Number(acct.current_balance)).toBeCloseTo(137000, 3);
});

test('both amounts typed, unrated sending side: books', async () => {
  const exec = await seeded('USD', 'KRW', 'USD');
  await transfer(exec, 137000, 100);
  const b = await booked(exec);
  expect(b.fromBase).toBeCloseTo(-100, 3);
  expect(b.to.base).toBeCloseTo(100, 3);
  expect(b.fxLegs).toBe(0);
  expect(b.rates).toBe(0);
});

test('the base side values the other, even when the base itself has no rate', async () => {
  const exec = await seeded('KRW', 'KRW', 'USD');
  await transfer(exec, 137000, 100);
  const b = await booked(exec);
  expect(b.to.base).toBeCloseTo(137000, 3);
  expect(b.fxLegs).toBe(0);
  expect(b.rates).toBe(0);
});

test('only the sent amount: still refused, nothing written', async () => {
  const exec = await seeded();
  await noRate(transfer(exec, 100, null));
  expect(await exec('SELECT * FROM entries')).toEqual([]);
});

test('neither side can be valued in base: still refused, nothing written', async () => {
  const exec = await seeded('USD', 'KRW', 'VND');
  await noRate(transfer(exec, 137000, 2_500_000));
  expect(await exec('SELECT * FROM entries')).toEqual([]);
  expect(await exec('SELECT * FROM exchange_rates')).toEqual([]);
});

test('both sides rated: each keeps its own rate and the FX leg, as before', async () => {
  const exec = await seeded();
  await applyMutation(exec, 'setExchangeRate', { date: '2026-05-16', currency: 'KRW', rate: 0.00072 });
  await transfer(exec);
  const b = await booked(exec);
  expect(b.to.base).toBeCloseTo(98.64, 3); // 137,000 × 0.00072
  expect(b.fxLegs).toBe(1);
  expect(b.sum).toBeCloseTo(0, 3);
});

test('moving the date re-values the legs without a rate', async () => {
  const exec = await seeded();
  await transfer(exec);
  const [p] = await exec("SELECT id FROM postings WHERE account_id = 'a2'");
  await applyMutation(exec, 'updateTransaction', { id: String(p.id), patch: { date: '2026-05-20' } });
  const b = await booked(exec);
  expect(b.to.base).toBeCloseTo(100, 3);
  expect(b.fxLegs).toBe(0);
  const [e] = await exec('SELECT date FROM entries');
  expect(String(e.date)).toBe('2026-05-20');
});

test('changing the base re-values every leg; the unrated one follows its partner', async () => {
  const exec = await seeded();
  await transfer(exec);
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'l1', newBase: 'EUR' });
  const b = await booked(exec);
  expect(b.fromBase).toBeCloseTo(-92, 3); // $100 at EUR's static 1.087
  expect(b.to.base).toBeCloseTo(-b.fromBase, 3);
  expect(b.fxLegs).toBe(0);
});

// --- Editing a transfer valued from its partner, after a rate appears ---

const setRate = (exec: Exec, date: string, rate: number, currency = 'KRW') =>
  applyMutation(exec, 'setExchangeRate', { date, currency, rate });

const krwRows = async (exec: Exec) =>
  (await exec("SELECT date FROM exchange_rates WHERE currency = 'KRW' ORDER BY date")).map((r) => String(r.date));

/** The pairing, unchanged: the KRW leg is still worth exactly the dollars, at
 *  the rate the two amounts imply, with no FX leg. */
async function expectPaired(exec: Exec, usd = 100, krw = 137000) {
  const b = await booked(exec);
  expect(b.fromBase).toBeCloseTo(-usd, 3);
  expect(b.to.amount).toBeCloseTo(krw, 3);
  expect(b.to.base).toBeCloseTo(usd, 3);
  expect(b.to.rate).toBeCloseTo(Math.round((usd / krw) * 1e6) / 1e6, 9);
  expect(b.fxLegs).toBe(0);
  expect(b.sum).toBeCloseTo(0, 3);
}

const entryId = async (exec: Exec) => String((await exec('SELECT id FROM entries'))[0].id);
const toPosting = async (exec: Exec) => String((await exec("SELECT id FROM postings WHERE account_id = 'a2'"))[0].id);

test('a later rate, then a note edit: the transfer stays as booked', async () => {
  const exec = await seeded();
  await transfer(exec);
  await setRate(exec, '2026-10-19', 0.0007);
  await applyMutation(exec, 'updateTransfer', { id: await entryId(exec), patch: { note: 'rent deposit' } });
  await expectPaired(exec);
  expect(await krwRows(exec)).toEqual(['2026-10-19']);
});

test('a later rate, then a date move: still paired, the later rate not reached back for', async () => {
  const exec = await seeded();
  await transfer(exec);
  await setRate(exec, '2026-10-19', 0.0007);
  await applyMutation(exec, 'updateTransaction', { id: await toPosting(exec), patch: { date: '2026-05-20' } });
  await expectPaired(exec);
  expect(await krwRows(exec)).toEqual(['2026-10-19']);
});

test('a later rate, then a base change: the KRW leg still follows the dollars', async () => {
  const exec = await seeded();
  await transfer(exec);
  await setRate(exec, '2026-10-19', 0.0007);
  await applyMutation(exec, 'changeLedgerBase', { ledgerId: 'l1', newBase: 'EUR' });
  const b = await booked(exec);
  expect(b.fromBase).toBeCloseTo(-92, 3); // $100 at EUR's static 1.087
  expect(b.to.base).toBeCloseTo(-b.fromBase, 3);
  expect(b.fxLegs).toBe(0);
  expect(await krwRows(exec)).toEqual(['2026-10-19']);
});

test('both amounts changed through updateTransfer: the legs stay paired', async () => {
  const exec = await seeded();
  await transfer(exec);
  await applyMutation(exec, 'updateTransfer', { id: await entryId(exec), patch: { fromAmount: 100, toAmount: 140000 } });
  await expectPaired(exec, 100, 140000); // was a $2.19 FX leg
  await applyMutation(exec, 'updateTransfer', { id: await entryId(exec), patch: { fromAmount: 120 } });
  await expectPaired(exec, 120, 168000);
});

test('a rate dated on or before the transfer: a re-valuation uses it, as a fresh booking would', async () => {
  const exec = await seeded();
  await transfer(exec);
  await setRate(exec, '2026-05-01', 0.00072);
  await applyMutation(exec, 'updateTransfer', { id: await entryId(exec), patch: { note: 'still as booked' } });
  await expectPaired(exec);
  await applyMutation(exec, 'updateTransaction', { id: await toPosting(exec), patch: { date: '2026-05-20' } });
  const b = await booked(exec);
  expect(b.to.base).toBeCloseTo(98.64, 3); // 137,000 × 0.00072
  expect(b.fxLegs).toBe(1);
  expect(b.sum).toBeCloseTo(0, 3);
});

test('booking when the only rate is dated later: valued from the partner, nothing saved under its date', async () => {
  const exec = await seeded();
  await setRate(exec, '2026-10-19', 0.0007);
  await transfer(exec);
  await expectPaired(exec);
  expect(await krwRows(exec)).toEqual(['2026-10-19']);
});
