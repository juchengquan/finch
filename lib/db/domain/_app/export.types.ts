// lib/db/domain/_app/export.types.ts — public row shapes for the export
// utility (CSV row shape + filter). Keep this file free of SQL imports —
// it should be safe to import from any layer (UI components, route handlers,
// app_state) without pulling in the DB driver.

export interface TxExportRow {
  date: string;
  time: string;
  ledger: string;
  account: string;
  merchant: string;
  category: string;
  amount: number;
  currency: string;
  amountBase: number;
  status: string;
  kind: string;
  note: string;
  tags: string;
}

/** Optional scoping for a transactions export. Both filters are independent;
 *  omit for the full all-ledgers export (the Settings backup behaviour). */
export interface TxExportFilter {
  /** Restrict to one ledger. */
  ledgerId?: string;
  /** Restrict to a single YYYY-MM month (matched against the txn date). */
  month?: string;
}
