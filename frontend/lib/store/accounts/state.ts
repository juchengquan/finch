// frontend/lib/store/accounts/state.ts — accounts-domain slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in accounts/actions.ts.

import type { AccountRow } from '@/lib/db/domain/accounts/types';

export const accountsInitial = {
  accounts: [] as AccountRow[],
} as const;
