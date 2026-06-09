// lib/db/domain/accounts/types.ts — public row + input/patch shapes for the
// accounts domain. Keep this file free of SQL imports — it should be safe to
// import from any layer (UI components, route handlers, app_state) without
// pulling in the DB driver.

export interface AccountRow {
  id: string;
  ledgerId: string;
  name: string;
  type: string;
  currency: string;
  balance: number;
  /** Opening balance in the account's native currency. The starting point that
   *  `recomputeAccount` walks forward through confirmed rows to land at
   *  `current_balance`; same anchor the reconcile selector uses. */
  openingBalance: number;
  /** Ledger-base value of the opening balance, locked at account creation. The
   *  cost-basis half of the unrealized-FX calculation: cost basis =
   *  openingBalanceBase + Σ amount_base of confirmed transactions. */
  openingBalanceBase: number;
  groupId: string | null;
  groupName: string | null;
  includeInNetWorth: number; // 0/1; defaulted from `type` at create, flippable per account
  isActive: boolean; // mirrors accounts.is_active (1 = active, 0 = archived)
  color: string | null;
  sortOrder: number;
  /** Date of the last successful reconcile-to-statement (`YYYY-MM-DD`), or null
   *  when the account has never been reconciled. */
  lastReconciledAt: string | null;
  /** Statement balance the user matched at that date, in the account's native
   *  currency. Paired with `lastReconciledAt`. */
  lastReconciledBalance: number | null;
  /** ISO 8601 UTC stamp set by `archiveAccount` when the row was soft-deleted,
   *  `null` while the account is active. Powers the "Archived <date>" subtitle
   *  on the ghost-row variant in the Accounts list. */
  archivedAt: string | null;
}

// `currency` is intentionally not editable — it's fixed at account creation
// (changing it would re-interpret stored native amounts / locked amount_base).
export interface AccountPatch {
  name?: string;
  type?: string;
  color?: string | null;
  groupId?: string | null;
  /** Per-account net-worth flag. Defaulted from `type` on create; flippable. */
  includeInNetWorth?: number;
}

export interface NewAccount {
  id: string;
  ledgerId: string;
  name: string;
  type: string;
  currency: string;
  groupId: string | null;
  openingBalance: number;
  color: string | null;
}
