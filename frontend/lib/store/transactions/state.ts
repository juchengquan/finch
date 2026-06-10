// frontend/lib/store/transactions/state.ts — transactions-domain slice of
// the initial state. Pure data; the action creators (added in Task 4)
// live in transactions/actions.ts. `attachments` is part of the
// transactions slice (they're projected off transactions, not their own
// domain). The `scheduled` array lives in scheduled/state.ts; `transfers`
// don't own a state slice (they're two transaction rows sharing a
// `transferGroupId`).

import type { Tx } from '@/lib/store';
import type { Attachment } from '@/lib/db/domain/attachments/types';

export const transactionsInitial = {
  transactions: [] as Tx[],
  attachments: [] as Attachment[],
} as const;
