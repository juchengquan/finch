// frontend/lib/store/ledgers/state.ts — ledgers-domain slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in ledgers/actions.ts.

import type { LedgerRow } from '@/lib/db/domain/ledgers/types';

export const ledgersInitial = {
  ledgers: [] as LedgerRow[],
} as const;
