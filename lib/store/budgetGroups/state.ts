// frontend/lib/store/budgetGroups/state.ts — budgetGroups-domain slice of
// the initial state. Pure data; the action creators (added in Task 4)
// live in budgetGroups/actions.ts.

import type { BudgetGroupRow } from '@/lib/db/domain/budgetGroups/types';

export const budgetGroupsInitial = {
  budgetGroups: [] as BudgetGroupRow[],
} as const;
