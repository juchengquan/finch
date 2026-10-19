// Currency conversion against the exchange_rates table.
//
// Rates are stored as `rate` = USD per 1 unit of `currency` (USD is the
// universal hub; USD itself is never stored — its rate is 1 by definition).
// Cross-rate is derived via the hub:
//   rate(C → B) = rate_to_usd(C) / rate_to_usd(B)
//
// The table is an append-only record: rows are never pruned (a decade of
// daily rates for every supported currency is ~1 MB — there is no size
// problem to solve). It holds only rates the user typed, fetched or
// imported; a conversion saves nothing back. Each posting stores the rate it
// was booked at (exchange_rate + amount_base), and re-deriving one (an edit
// that moves its amount or date, recomputeAmountBases on a base-currency
// change) looks the rate up afresh, so a corrected rate reaches it.
//
// Lookup order for a date with no stored row (backdate or missing currency):
//   1. nearest stored rate on-or-before the txn date
//   2. nearest stored rate on-or-after the txn date (closest in time)
//   3. static FALLBACK_USD_PER_UNIT map (works on an empty table)
//   4. nothing — convertToBase refuses the write (`error.fx.noRate`)
// Rows tagged 'derived' are skipped at every step. Older versions pinned the
// resolved rate under each conversion's date with that tag, and as the
// nearest row the copy outranked the rate it was copied from: correcting a
// mistyped rate, or adding a closer one, changed nothing for later entries.
//
// Step 4 used to be "1": ₩50,000 was booked as 50,000 USD, and the 1.0 was
// pinned as a 'derived' row, which converted the currency 1:1 for every date
// after it until the lookup stopped reading such rows.

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

/**
 * USD-per-1-unit of `currency`, looked up against the table at `date`:
 *   1. exact / nearest on-or-before, else
 *   2. nearest on-or-after, else
 *   3. static fallback, else
 *   4. null — there is no rate.
 * 'derived' rows (copies older versions saved) never count — see the header.
 * USD itself is the hub and short-circuits to 1. Reads only.
 */
export async function rateToHub(exec: Exec, currency: string, date: string): Promise<number | null> {
  if (currency === HUB_CURRENCY) return 1;
  const before = await exec(
    "SELECT rate AS r FROM exchange_rates WHERE currency = ? AND date <= ? AND COALESCE(source, '') <> 'derived' ORDER BY date DESC LIMIT 1",
    [currency, date],
  );
  if (before.length) return Number(before[0].r);
  const after = await exec(
    "SELECT rate AS r FROM exchange_rates WHERE currency = ? AND date >= ? AND COALESCE(source, '') <> 'derived' ORDER BY date ASC LIMIT 1",
    [currency, date],
  );
  if (after.length) return Number(after[0].r);
  return FALLBACK_USD_PER_UNIT[currency] ?? null;
}

export interface Conversion {
  amountBase: number; // `native` expressed in `base`, rounded to 2dp
  rate: number; // the C→B rate that was applied
}

/** Convert a native amount into the base currency via the USD pivot, as-of `date`.
 *  A side with no rate at all refuses (`error.fx.noRate`) rather than converting
 *  1:1. Reads only. */
export async function convertToBase(
  exec: Exec,
  native: number,
  currency: string,
  base: string,
  date: string,
): Promise<Conversion> {
  if (currency === base) return { amountBase: native, rate: 1 };
  const rc = await rateToHub(exec, currency, date);
  const rb = await rateToHub(exec, base, date);
  if (rc === null || rb === null) {
    const missing = rc !== null ? base : currency;
    throw new I18nError('error.fx.noRate', { from: currency, to: base, currency: missing },
      `No exchange rate for ${currency} → ${base} yet. Add a ${missing} rate on the FX page.`);
  }
  const rate = rb !== 0 ? rc / rb : 1;
  return { amountBase: Math.round(native * rate * 100) / 100, rate: Math.round(rate * 1e6) / 1e6 };
}
