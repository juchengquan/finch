// lib/db/domain/_app/system.types.ts — public row shapes for the system
// utility (exchange rates). Keep this file free of SQL imports — it should
// be safe to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

export interface ExchangeRate {
  date: string;
  currency: string;
  rate: number;
  source: string | null;
}
