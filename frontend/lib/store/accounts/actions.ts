// frontend/lib/store/accounts/actions.ts — account action creators.
// Extracted from lib/store.ts:649-677 (createAccount, updateAccount,
// archiveAccount, unarchiveAccount).
//
// `NewAccountInput` is the client-side input shape (the DB-side
// `NewAccount` includes an `id` and required `ledgerId`; this type
// is the variant the UI passes before the action assigns defaults).
// `AccountPatch` is re-used from the DB types since the shapes match.

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';
import type { AccountPatch } from '@/lib/db/domain/accounts/types';

export interface NewAccountInput {
  name: string;
  type: string;
  currency?: string;
  groupId?: string | null;
  openingBalance?: number;
  color?: string | null;
  ledgerId?: string;
}

export const accountActions = (set: SetState, get: GetState) => ({
  createAccount: (input: NewAccountInput): string => {
    const id = newId('acct', { long: false });
    syncMutation('createAccount', {
      id,
      ledgerId: input.ledgerId ?? 'personal',
      name: input.name,
      type: input.type,
      currency: input.currency ?? 'SGD',
      groupId: input.groupId ?? null,
      openingBalance: input.openingBalance ?? 0,
      color: input.color ?? null,
    });
    return id;
  },

  updateAccount: (id: string, patch: AccountPatch): void => {
    // Optimistically patch the projected row; syncMutation re-projects from the DB.
    set((s) => ({ accounts: s.accounts.map((a) => (a.id === id ? { ...a, ...patch } : a)) }));
    syncMutation('updateAccount', { id, patch });
  },

  archiveAccount: (id: string): void => {
    set((s) => ({ accounts: s.accounts.filter((a) => a.id !== id) }));
    syncMutation('archiveAccount', { id });
  },

  unarchiveAccount: (id: string): void => {
    syncMutation('unarchiveAccount', { id });
  },
});
