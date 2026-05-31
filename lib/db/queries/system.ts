// Read queries for the System screen: exchange rates and synced devices.

import type { Exec } from '@/lib/db/repo';

export interface ExchangeRate {
  date: string;
  currency: string;
  rate: number;
  source: string | null;
}

export interface Device {
  id: string;
  name: string;
  lastSync: string;
  lastTxn: string | null;
  current: boolean;
}

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

export async function listDevices(exec: Exec): Promise<Device[]> {
  const rows = await exec('SELECT device_id, device_name, last_sync_at, last_txn_id, is_current FROM sync_log ORDER BY is_current DESC, device_name');
  return rows.map((r) => ({
    id: String(r.device_id),
    name: String(r.device_name),
    lastSync: String(r.last_sync_at),
    lastTxn: r.last_txn_id == null ? null : String(r.last_txn_id),
    current: !!Number(r.is_current),
  }));
}
