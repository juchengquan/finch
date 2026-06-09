// lib/db/domain/categories/types.ts — public row + input/patch shapes for
// the categories domain. Keep this file free of SQL imports — it should be
// safe to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

export interface CategoryRow {
  id: string;
  ledgerId: string;
  /** NULL = top-level category. Non-NULL = child whose parent is a top-level row. */
  parentId: string | null;
  name: string;
  /** `expense` / `income` / `transfer`. (DB column is `kind` for historical reasons.) */
  type: string;
  icon: string | null;
  /** Hex `#rrggbb`. Use lib/colors `categoryHex(hue)` to generate from a palette hue. */
  color: string | null;
}

export interface CategoryTreeNode {
  parent: CategoryRow;
  children: CategoryRow[];
}

export interface CategoryPatch {
  name?: string;
  type?: string;
  icon?: string | null;
  color?: string | null;
  parentId?: string | null;
}

export interface CategorySpend {
  id: string;
  name: string;
  spent: number; // positive magnitude of expenses
}
