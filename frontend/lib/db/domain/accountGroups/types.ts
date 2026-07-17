// lib/db/domain/accountGroups/types.ts — public row + input/patch shapes for
// the account groups domain. Keep this file free of SQL imports — it should
// be safe to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

export interface AccountGroupRow {
  id: string;
  ledgerId: string;
  name: string;
  /** Optional accent color (hex), shared with the iOS engine; null = none. */
  color: string | null;
  sortOrder: number;
}

export interface NewAccountGroup {
  id: string;
  ledgerId: string;
  name: string;
  color?: string | null;
}

export interface AccountGroupPatch {
  name?: string;
  /** Set to a hex string, or null to clear. */
  color?: string | null;
  /** Position among the ledger's groups — written by drag-to-reorder. */
  sortOrder?: number;
}
