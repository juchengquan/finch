// Currency conversion via the USD-pivoted exchange_rates table (mirrors the
// server-side queries/rates.ts logic for client-side display). Pure functions
// — `useMoney` calls these against the projected store rates.

import type { ExchangeRate } from '@/lib/db/queries/system';
import { HUB_CURRENCY } from '@/lib/db/queries/rates';

/** Latest USD-per-1-unit rate per currency. USD always = 1 (the hub). */
export function latestRateMap(rates: ExchangeRate[]): Map<string, number> {
  const latest = new Map<string, { date: string; rate: number }>();
  for (const r of rates) {
    const prev = latest.get(r.currency);
    if (!prev || r.date > prev.date) latest.set(r.currency, { date: r.date, rate: r.rate });
  }
  const m = new Map<string, number>();
  for (const [cur, v] of latest) m.set(cur, v.rate);
  m.set(HUB_CURRENCY, 1);
  return m;
}

/**
 * Convert `amount` from `from`-currency into `to`-currency via the USD pivot.
 * Returns `null` when either currency has no rate (callers fall back to the
 * static table so a value is always produced).
 */
export function convertViaRates(
  amount: number,
  from: string,
  to: string,
  rateMap: Map<string, number>,
): number | null {
  if (from === to) return amount;
  const rf = rateMap.get(from);
  const rt = rateMap.get(to);
  if (rf == null || rt == null || rt === 0) return null;
  return (amount * rf) / rt;
}
