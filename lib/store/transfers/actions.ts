// frontend/lib/store/transfers/actions.ts — transfer action creators.
// Extracted from lib/store.ts:876-878 (createTransfer) + lib/store.ts:1047-1057
// (updateTransfer, deleteTransfer).
//
// Transfers are special: they're pairs of transactions (the two legs of the
// transfer) bound by a `transferGroupId`. The server creates the multi-row
// shape on insert; the client just optimistically drops both legs on
// delete (sharing the group id).

import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';
import type { TransferInput } from './state';

export const transferActions = (set: SetState, get: GetState) => ({
  // Transfers are created on the server (multi-row / relational); the server
  // response refreshes the store. (Scheduled "post" is called directly from
  // the scheduled page so it can surface account-match errors.)
  createTransfer: (input: TransferInput): void => {
    syncMutation('createTransfer', { ...input });
  },

  updateTransfer: (
    id: string,
    patch: { fromAmount?: number; toAmount?: number; date?: string; time?: string | null; note?: string | null },
  ): void => {
    // Both legs are rewritten + balances recomputed server-side; adopt the
    // server's re-projection rather than re-deriving the legs client-side.
    syncMutation('updateTransfer', { id, patch });
  },

  deleteTransfer: (id: string): void => {
    // A transfer is two transactions sharing a group id; drop both optimistically.
    set((s) => ({ transactions: s.transactions.filter((t) => t.transferGroupId !== id) }));
    syncMutation('deleteTransfer', { id });
  },
});
