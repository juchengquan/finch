// lib/db/domain/budgetGroups/types.ts — public row + input/patch shapes for
// the budget groups domain. Keep this file free of SQL imports — it should
// be safe to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

export interface BudgetGroupRow {
  id: string;
  ledgerId: string;
  name: string;
  /** Optional accent color (hex), shared with the iOS engine; null = none. */
  color: string | null;
  sortOrder: number;
}

export interface NewBudgetGroup {
  id: string;
  ledgerId: string;
  name: string;
  color?: string | null;
}

export interface BudgetGroupPatch {
  name?: string;
  /** Set to a hex string, or null to clear. */
  color?: string | null;
  /** Position among the ledger's budget groups — written by drag-to-reorder. */
  sortOrder?: number;
}
