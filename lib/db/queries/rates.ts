// Currency conversion against the exchange_rates table. Rates are stored as
// rate_to_sgd, so cross-base conversion pivots through SGD:
//   rate(C→B) = rate_to_sgd(C) / rate_to_sgd(B)
// Rates are resolved as-of a date (nearest row on or before it); when the table
// has no row, we fall back to a static units-per-USD map so a value is always
// produced (callers lock the result on the transaction).

import type { Exec } from '@/lib/db/repo';

// Units per 1 USD; fallback rate_to_sgd(cur) = SGD-per-USD / cur-per-USD.
const RATE_PER_USD: Record<string, number> = { USD: 1, EUR: 0.92, GBP: 0.79, JPY: 156.4, SGD: 1.35, CNY: 7.24 };
function fallbackToSgd(currency: string): number {
  const perUsd = RATE_PER_USD[currency];
  return perUsd ? RATE_PER_USD.SGD / perUsd : 1;
}

/** The base currency a ledger's `amount_base` figures are expressed in. */
export async function ledgerBaseCurrency(exec: Exec, ledgerId: string): Promise<string> {
  const rows = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [ledgerId]);
  return rows.length ? String(rows[0].base_currency) : 'USD';
}

/** rate_to_sgd for a currency, nearest row on or before `date`; SGD → 1; else fallback. */
export async function rateToSgd(exec: Exec, currency: string, date: string): Promise<number> {
  if (currency === 'SGD') return 1;
  const rows = await exec(
    'SELECT rate_to_sgd AS r FROM exchange_rates WHERE currency = ? AND date <= ? ORDER BY date DESC LIMIT 1',
    [currency, date],
  );
  return rows.length ? Number(rows[0].r) : fallbackToSgd(currency);
}

export interface Conversion {
  amountBase: number; // `native` expressed in `base`, rounded to 2dp
  rate: number; // the C→B rate that was applied
}

/** Convert a native amount into the base currency via the SGD pivot, as-of `date`. */
export async function convertToBase(
  exec: Exec,
  native: number,
  currency: string,
  base: string,
  date: string,
): Promise<Conversion> {
  if (currency === base) return { amountBase: native, rate: 1 };
  const [rc, rb] = await Promise.all([rateToSgd(exec, currency, date), rateToSgd(exec, base, date)]);
  const rate = rb !== 0 ? rc / rb : 1;
  return { amountBase: Math.round(native * rate * 100) / 100, rate: Math.round(rate * 1e6) / 1e6 };
}
