// lib/db/domain/budgetGroups/types.ts — public row + input/patch shapes for
// the budget groups domain. Keep this file free of SQL imports — it should
// be safe to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

export interface BudgetGroupRow {
  id: string;
  ledgerId: string;
  name: string;
  sortOrder: number;
}

export interface NewBudgetGroup {
  id: string;
  ledgerId: string;
  name: string;
}

export interface BudgetGroupPatch {
  name?: string;
  /** Position among the ledger's budget groups — written by drag-to-reorder. */
  sortOrder?: number;
}
