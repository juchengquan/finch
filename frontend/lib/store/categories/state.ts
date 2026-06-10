// frontend/lib/store/categories/state.ts — categories-domain slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in categories/actions.ts.

import type { CategoryRow } from '@/lib/db/domain/categories/types';

export const categoriesInitial = {
  categories: [] as CategoryRow[],
} as const;
