// Currency conversion against the exchange_rates table.
//
// Rates are stored as `rate` = USD per 1 unit of `currency` (USD is the
// universal hub; USD itself is never stored — its rate is 1 by definition).
// Cross-rate is derived via the hub:
//   rate(C → B) = rate_to_usd(C) / rate_to_usd(B)
//
// The table is a lookup cache, not a permanent record: every confirmed
// foreign-currency transaction locks the rate it used on its own row
// (transactions.exchange_rate + amount_base), so pruning old rows never
// breaks historical display. We keep a rolling window (RATE_RETENTION_DAYS)
// so the FX page can show recent trends and backdates within the window
// resolve precisely.
//
// Lookup order for a cache miss (txn date outside the window or currency
// missing entirely):
//   1. nearest stored rate on-or-before the txn date
//   2. nearest stored rate on-or-after the txn date (closest in time)
//   3. static FALLBACK_USD_PER_UNIT map (works on an empty table)

import type { Exec } from '@/lib/db/repo';

/** The universal pivot currency. exchange_rates.rate is always vs this. */
export const HUB_CURRENCY = 'USD';

/** Sliding-window retention. Rows older than this are pruned on rate writes. */
export const RATE_RETENTION_DAYS = 90;

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
 *   1. nearest on-or-before, else
 *   2. nearest on-or-after, else
 *   3. static fallback.
 * USD itself is the hub and short-circuits to 1.
 */
export async function rateToHub(exec: Exec, currency: string, date: string): Promise<number> {
  if (currency === HUB_CURRENCY) return 1;
  const before = await exec(
    'SELECT rate AS r FROM exchange_rates WHERE currency = ? AND date <= ? ORDER BY date DESC LIMIT 1',
    [currency, date],
  );
  if (before.length) return Number(before[0].r);
  const after = await exec(
    'SELECT rate AS r FROM exchange_rates WHERE currency = ? AND date >= ? ORDER BY date ASC LIMIT 1',
    [currency, date],
  );
  if (after.length) return Number(after[0].r);
  return staticFallback(currency);
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

/**
 * Prune rates older than the retention window, computed against the latest
 * stored date (not `now()`) so a long-idle DB doesn't lose its only history.
 * Safe to call after every write — it's a single DELETE.
 */
export async function pruneOldRates(exec: Exec, daysToKeep = RATE_RETENTION_DAYS): Promise<void> {
  const rows = await exec('SELECT MAX(date) AS latest FROM exchange_rates');
  const latest = rows[0]?.latest;
  if (!latest) return;
  // SQLite date arithmetic — cutoff = latest minus `daysToKeep` days.
  await exec(
    "DELETE FROM exchange_rates WHERE date < date(?, ?)",
    [String(latest), `-${daysToKeep} days`],
  );
}
