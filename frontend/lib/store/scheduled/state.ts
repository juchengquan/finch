// frontend/lib/store/scheduled/state.ts — scheduled-domain slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in scheduled/actions.ts.
//
// Also owns the data-type definitions (ScheduledTemplate, ScheduledSplit)
// that were previously declared in lib/store.ts:87-129. They live here
// (the scheduled domain's state file) because every consumer of these
// types is the scheduled domain or its consumers. Re-exported from
// lib/store/index.ts so the existing
// `import type { ScheduledTemplate } from '@/lib/store'` paths keep
// working during the migration.

export interface ScheduledSplit {
  /** FK to the destination account. `account` is its display name, derived. */
  accountId: string;
  account: string;
  pct: number;
  abs: number | null;
  label: string;
}

export interface ScheduledTemplate {
  id: string;
  name: string;
  /** Description stamped onto posted transactions; falls back to `name`. */
  description?: string | null;
  type: string;
  amount: number | null;
  varies?: number;
  frequency: string;
  dayOfMonth: number;
  weekDay?: number;
  /** FK to the primary account (the destination for a transfer). `account` is
   *  its display name, derived by joining accounts at read time. */
  accountId: string;
  account: string;
  /** Source account for a transfer (FK); `from` is its display name. */
  fromAccountId?: string;
  from?: string;
  autoPost: number;
  nextRun: string;
  lastRun: string;
  color?: string | null;
  category?: string | null;
  startDate?: string;
  endDate?: string | null;
  maxExecutions?: number | null;
  /** Total payments in a finite installment plan (e.g. 24 for a 24-month
   *  phone contract). Null = ordinary recurring expense, no end in sight. */
  installmentTotal?: number | null;
  /** Payments posted so far. Auto-incremented when the template posts; when
   *  it reaches installmentTotal the template flips to inactive. */
  installmentPaid?: number;
  splits?: ScheduledSplit[];
}

export const scheduledInitial = {
  scheduled: [] as ScheduledTemplate[],
} as const;
