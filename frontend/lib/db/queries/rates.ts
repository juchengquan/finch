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
// The resolved rate is then pinned under the requested date (source
// 'derived') so the approximation is at least stable across future lookups.

import type { Exec } from '../core/repo';

/** The universal pivot currency. exchange_rates.rate is always vs this. */
export const HUB_CURRENCY = 'USD';

// Static last-resort map (USD per 1 unit of currency). Used only when the
// rates table has no rows at all for a currency — keeps the app working on
// an empty/fresh DB.
const FALLBACK_USD_PER_UNIT: Record<string, number> = {
  USD: 1,
  EUR: 1.087,
  GBP: 1.266,
  JPY: 0.0064,
  SGD: 0.741,
  CNY: 0.138,
};
function staticFallback(currency: string): number {
  return FALLBACK_USD_PER_UNIT[currency] ?? 1;
}

/** The base currency a ledger's `amount_base` figures are expressed in. */
export async function ledgerBaseCurrency(exec: Exec, ledgerId: string): Promise<string> {
  const rows = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [ledgerId]);
  return rows.length ? String(rows[0].base_currency) : 'USD';
}

/**
 * USD-per-1-unit of `currency`, looked up against the table at `date`:
 *   1. exact / nearest on-or-before, else
 *   2. nearest on-or-after, else
 *   3. static fallback.
 * USD itself is the hub and short-circuits to 1.
 *
 * Write-through: when no exact-date row exists, the resolved rate is pinned
 * under `date` (source 'derived', INSERT OR IGNORE so a user-set rate is
 * never clobbered). Every conversion the app locks onto a row is thereby
 * reproducible — a later recompute at the same date finds the same rate even
 * if neighboring rows change.
 */
export async function rateToHub(exec: Exec, currency: string, date: string): Promise<number> {
  if (currency === HUB_CURRENCY) return 1;
  const before = await exec(
    'SELECT date AS d, rate AS r FROM exchange_rates WHERE currency = ? AND date <= ? ORDER BY date DESC LIMIT 1',
    [currency, date],
  );
  if (before.length && String(before[0].d) === date) return Number(before[0].r);
  let rate: number;
  if (before.length) {
    rate = Number(before[0].r);
  } else {
    const after = await exec(
      'SELECT rate AS r FROM exchange_rates WHERE currency = ? AND date >= ? ORDER BY date ASC LIMIT 1',
      [currency, date],
    );
    rate = after.length ? Number(after[0].r) : staticFallback(currency);
  }
  await exec(
    "INSERT OR IGNORE INTO exchange_rates (date, currency, rate, source) VALUES (?, ?, ?, 'derived')",
    [date, currency, rate],
  );
  return rate;
}

export interface Conversion {
  amountBase: number; // `native` expressed in `base`, rounded to 2dp
  rate: number; // the C→B rate that was applied
}

/** Convert a native amount into the base currency via the USD pivot, as-of `date`. */
export async function convertToBase(
  exec: Exec,
  native: number,
  currency: string,
  base: string,
  date: string,
): Promise<Conversion> {
  if (currency === base) return { amountBase: native, rate: 1 };
  const [rc, rb] = await Promise.all([rateToHub(exec, currency, date), rateToHub(exec, base, date)]);
  const rate = rb !== 0 ? rc / rb : 1;
  return { amountBase: Math.round(native * rate * 100) / 100, rate: Math.round(rate * 1e6) / 1e6 };
}
