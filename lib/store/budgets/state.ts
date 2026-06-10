// frontend/lib/store/budgets/state.ts — budgets-domain slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in budgets/actions.ts.

import type { BudgetRow } from '@/lib/db/domain/budgets/types';

export const budgetsInitial = {
  budgets: [] as BudgetRow[],
} as const;
