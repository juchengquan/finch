// lib/db/domain/counterparties/types.ts — public row + input/patch shapes for
// the counterparties domain. Keep this file free of SQL imports — it should
// be safe to import from any layer (UI components, route handlers, app_state)
// without pulling in the DB driver.

export interface Counterparty {
  id: string;
  ledgerId: string;
  name: string;
  verified: boolean;
}

export interface NewCounterparty {
  id: string;
  ledgerId: string;
  name: string;
}

export interface CounterpartyPatch {
  name?: string;
}
