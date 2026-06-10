// frontend/lib/store/holdings/state.ts — holdings-domain slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in holdings/actions.ts.

import type { Holding } from '@/lib/db/domain/holdings/types';

export const holdingsInitial = {
  holdings: [] as Holding[],
} as const;
