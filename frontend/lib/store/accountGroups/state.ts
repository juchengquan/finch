// frontend/lib/store/accountGroups/state.ts — accountGroups-domain slice
// of the initial state. Pure data; the action creators (added in Task 4)
// live in accountGroups/actions.ts.

import type { AccountGroupRow } from '@/lib/db/domain/accountGroups/types';

export const accountGroupsInitial = {
  accountGroups: [] as AccountGroupRow[],
} as const;
