// lib/db/domain/budgets/types.ts — public row + input/patch shapes for the
// budgets domain. Keep this file free of SQL imports — it should be safe to
// import from any layer (UI components, route handlers, app_state) without
// pulling in the DB driver.

export type BudgetType = 'expense' | 'income';

export interface BudgetRow {
  id: string;
  ledgerId: string;
  groupId: string | null;
  name: string;
  type: BudgetType;
  amount: number;
  /** Manual progress accumulator for one-shot income/goal budgets. */
  saved: number;
  carryForward: number;
  frequency: string;
  startDate: string;
  endDate: string | null;
  isRecurring: number;
  rollover: number;
  rolloverLimit: number | null;
  /** Staged amount change; activated at the next period boundary by
   *  rollBudgetsIfDue. null = no pending change. */
  pendingAmount: number | null;
  /** Catch-up marker for the rollover engine. null = never rolled. */
  lastRolledPeriod: string | null;
  accountIds: string[];
  categoryIds: string[];
  tagIds?: string[];
  counterpartyIds?: string[];
  warningPct: number;
}

export interface NewBudget {
  id: string;
  ledgerId: string;
  groupId?: string | null;
  name: string;
  type: BudgetType;
  amount: number;
  saved?: number;
  frequency: string;
  startDate: string;
  endDate?: string | null;
  isRecurring?: number;
  rollover?: number;
  rolloverLimit?: number | null;
  accountIds?: string[];
  categoryIds?: string[];
  tagIds?: string[];
  counterpartyIds?: string[];
  warningPct?: number;
}

export interface BudgetPatch {
  groupId?: string | null;
  name?: string;
  type?: BudgetType;
  amount?: number;
  saved?: number;
  frequency?: string;
  startDate?: string;
  endDate?: string | null;
  isRecurring?: number;
  rollover?: number;
  rolloverLimit?: number | null;
  accountIds?: string[];
  categoryIds?: string[];
  tagIds?: string[];
  counterpartyIds?: string[];
  warningPct?: number;
}

export interface BudgetCyclePatch {
  frequency: string;
  startDate: string;
  /** When omitted, the current `amount` carries over unchanged. */
  amount?: number;
  /** Optional end-date adjustment alongside the cycle change. */
  endDate?: string | null;
}
