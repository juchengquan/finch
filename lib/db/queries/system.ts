// Read queries for the exchange-rates surface (Settings › Ledger › Exchange rates).

import type { Exec } from '../core/repo';
import type { ExchangeRate } from '@/lib/db/domain/_app/system.types';

export async function listExchangeRates(exec: Exec): Promise<ExchangeRate[]> {
  const rows = await exec('SELECT date, currency, rate, source FROM exchange_rates ORDER BY date');
  return rows.map((r) => ({
    date: String(r.date),
    currency: String(r.currency),
    rate: Number(r.rate),
    source: r.source == null ? null : String(r.source),
  }));
}

/** Upsert an exchange rate on (date, currency). `rate` is USD per 1 unit of `currency`. */
export async function setExchangeRate(
  exec: Exec,
  input: { date: string; currency: string; rate: number; source?: string | null },
): Promise<void> {
  await exec(
    'INSERT OR REPLACE INTO exchange_rates (date, currency, rate, source) VALUES (?, ?, ?, ?)',
    [input.date, input.currency, input.rate, input.source ?? null],
  );
}

export async function deleteExchangeRate(exec: Exec, date: string, currency: string): Promise<void> {
  await exec('DELETE FROM exchange_rates WHERE date = ? AND currency = ?', [date, currency]);
}
