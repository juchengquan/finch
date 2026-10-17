// Currency conversion against the exchange_rates table.
//
// Rates are stored as `rate` = USD per 1 unit of `currency` (USD is the
// universal hub; USD itself is never stored — its rate is 1 by definition).
// Cross-rate is derived via the hub:
//   rate(C → B) = rate_to_usd(C) / rate_to_usd(B)
//
// The table is an append-only record: rows are never pruned (a decade of
// daily rates for every supported currency is ~1 MB — there is no size
// problem to solve), and every rate the app actually relies on is
// write-through persisted under the date it was used for (see rateToHub).
// That makes locked conversions reproducible forever: re-deriving a
// transaction's amount_base (e.g. recomputeAmountBases on a base-currency
// change) finds the same rate and produces the same figure, no matter how
// far in the past the transaction sits.
//
// Lookup order for a date with no stored row (backdate or missing currency):
//   1. nearest stored rate on-or-before the txn date
//   2. nearest stored rate on-or-after the txn date (closest in time)
//   3. static FALLBACK_USD_PER_UNIT map (works on an empty table)
//   4. nothing — convertToBase refuses the write (`error.fx.noRate`)
// The resolved rate is then pinned under the requested date (source
// 'derived') so the approximation is at least stable across future lookups.
//
// Step 4 used to be "1": ₩50,000 was booked as 50,000 USD, and the 1.0 was
// pinned, shadowing any real KRW rate added later for every date after it.

import type { Exec } from '../core/repo';
import { I18nError } from '@/lib/i18n-error';

/** The universal pivot currency. exchange_rates.rate is always vs this. */
export const HUB_CURRENCY = 'USD';

// Static last-resort map (USD per 1 unit of currency). Used only when the
// rates table has no rows at all for a currency — keeps the app working on
// an empty/fresh DB for these few. Any other currency has no fallback.
const FALLBACK_USD_PER_UNIT: Record<string, number> = {
  USD: 1,
  EUR: 1.087,
  GBP: 1.266,
  JPY: 0.0064,
  SGD: 0.741,
  CNY: 0.138,
};

/** The base currency a ledger's `amount_base` figures are expressed in. */
export async function ledgerBaseCurrency(exec: Exec, ledgerId: string): Promise<string> {
  const rows = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [ledgerId]);
  return rows.length ? String(rows[0].base_currency) : 'USD';
}

/** A resolved hub rate, and whether it must be pinned under the lookup date. */
interface HubRate { rate: number; pin: boolean }

/**
 * USD-per-1-unit of `currency`, looked up against the table at `date`:
 *   1. exact / nearest on-or-before, else
 *   2. nearest on-or-after, else
 *   3. static fallback, else
 *   4. null — there is no rate.
 * USD itself is the hub and short-circuits to 1. Reads only; `pinRate` writes.
 */
async function lookupRateToHub(exec: Exec, currency: string, date: string): Promise<HubRate | null> {
  if (currency === HUB_CURRENCY) return { rate: 1, pin: false };
  const before = await exec(
    'SELECT date AS d, rate AS r FROM exchange_rates WHERE currency = ? AND date <= ? ORDER BY date DESC LIMIT 1',
    [currency, date],
  );
  if (before.length && String(before[0].d) === date) return { rate: Number(before[0].r), pin: false };
  if (before.length) return { rate: Number(before[0].r), pin: true };
  const after = await exec(
    'SELECT rate AS r FROM exchange_rates WHERE currency = ? AND date >= ? ORDER BY date ASC LIMIT 1',
    [currency, date],
  );
  if (after.length) return { rate: Number(after[0].r), pin: true };
  const fallback = FALLBACK_USD_PER_UNIT[currency];
  return fallback === undefined ? null : { rate: fallback, pin: true };
}

/**
 * Write-through: when no exact-date row exists, the resolved rate is pinned
 * under `date` (source 'derived', INSERT OR IGNORE so a user-set rate is
 * never clobbered). Every conversion the app locks onto a row is thereby
 * reproducible — a later recompute at the same date finds the same rate even
 * if neighboring rows change.
 */
async function pinRate(exec: Exec, currency: string, date: string, r: HubRate): Promise<void> {
  if (!r.pin) return;
  await exec(
    "INSERT OR IGNORE INTO exchange_rates (date, currency, rate, source) VALUES (?, ?, ?, 'derived')",
    [date, currency, r.rate],
  );
}

/** USD-per-1-unit of `currency` at `date` (lookup + write-through), or null
 *  when there is no rate at all. */
export async function rateToHub(exec: Exec, currency: string, date: string): Promise<number | null> {
  const r = await lookupRateToHub(exec, currency, date);
  if (!r) return null;
  await pinRate(exec, currency, date, r);
  return r.rate;
}

export interface Conversion {
  amountBase: number; // `native` expressed in `base`, rounded to 2dp
  rate: number; // the C→B rate that was applied
}

/** Convert a native amount into the base currency via the USD pivot, as-of `date`.
 *  A side with no rate at all refuses (`error.fx.noRate`) rather than converting
 *  1:1. Both sides are looked up before either is pinned, so a refusal writes
 *  nothing. */
export async function convertToBase(
  exec: Exec,
  native: number,
  currency: string,
  base: string,
  date: string,
): Promise<Conversion> {
  if (currency === base) return { amountBase: native, rate: 1 };
  const c = await lookupRateToHub(exec, currency, date);
  const b = await lookupRateToHub(exec, base, date);
  if (!c || !b) {
    const missing = c ? base : currency;
    throw new I18nError('error.fx.noRate', { from: currency, to: base, currency: missing },
      `No exchange rate for ${currency} → ${base} yet. Add a ${missing} rate on the FX page.`);
  }
  await pinRate(exec, currency, date, c);
  await pinRate(exec, base, date, b);
  const rc = c.rate, rb = b.rate;
  const rate = rb !== 0 ? rc / rb : 1;
  return { amountBase: Math.round(native * rate * 100) / 100, rate: Math.round(rate * 1e6) / 1e6 };
}
