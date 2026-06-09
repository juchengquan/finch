// lib/db/domain/holdings/types.ts — public row + input/patch shapes for the
// holdings domain. Keep this file free of SQL imports — it should be safe
// to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

export interface Holding {
  id: string;
  ledgerId: string;
  accountId: string;
  symbol: string;
  name: string | null;
  shares: number;
  /** Total amount paid in `currency`. Per-share average = costBasis / shares. */
  costBasis: number;
  currency: string;
  /** Last price the user logged (per share, in `currency`). Null until set. */
  lastPrice: number | null;
  /** YYYY-MM-DD the lastPrice was effective on. Null until set. */
  lastPriceDate: string | null;
  notes: string | null;
}

export interface NewHolding {
  id: string;
  ledgerId: string;
  accountId: string;
  symbol: string;
  name?: string | null;
  shares: number;
  costBasis: number;
  /** Defaults to the account's currency when omitted. */
  currency?: string;
  /** Optional initial price; pair with lastPriceDate when provided. */
  lastPrice?: number | null;
  lastPriceDate?: string | null;
  notes?: string | null;
}

export interface HoldingPatch {
  symbol?: string;
  name?: string | null;
  shares?: number;
  costBasis?: number;
  notes?: string | null;
}
