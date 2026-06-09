// lib/db/domain/ledgers/types.ts — public row + input/patch shapes for the
// ledgers domain. Keep this file free of SQL imports — it should be safe to
// import from any layer (UI components, route handlers, app_state) without
// pulling in the DB driver.

export interface LedgerRow {
  id: string;
  name: string;
  base: string;
  isDefault: number;
  /** Accent dot in the switcher; null = derive a hue from the id. */
  color: string | null;
  /** One-line description shown in the switcher dropdown. */
  tagline: string | null;
  /** Live count of active accounts in this ledger (subselect). */
  accounts: number;
  /** Live count of transactions in this ledger (subselect). */
  txns: number;
}

export interface NewLedgerInput {
  id: string;
  name: string;
  base: string;
  color?: string | null;
  tagline?: string | null;
}

export interface LedgerPatch {
  name?: string;
  color?: string | null;
  tagline?: string | null;
}
