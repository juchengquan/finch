// lib/db/domain/accountGroups/types.ts — public row + input/patch shapes for
// the account groups domain. Keep this file free of SQL imports — it should
// be safe to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

export interface AccountGroupRow {
  id: string;
  ledgerId: string;
  name: string;
  sortOrder: number;
}

export interface NewAccountGroup {
  id: string;
  ledgerId: string;
  name: string;
}

export interface AccountGroupPatch {
  name?: string;
}
