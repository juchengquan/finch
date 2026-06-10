// frontend/lib/store/counterparties/state.ts — counterparties-domain slice
// of the initial state. Pure data; the action creators (added in Task 4)
// live in counterparties/actions.ts.

import type { Counterparty } from '@/lib/db/domain/counterparties/types';

export const counterpartiesInitial = {
  counterparties: [] as Counterparty[],
} as const;
