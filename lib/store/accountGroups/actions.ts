// frontend/lib/store/accountGroups/actions.ts — account group action creators.
// Extracted from lib/store.ts:679-704 (createAccountGroup, updateAccountGroup,
// deleteAccountGroup).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';

export const accountGroupActions = (set: SetState, get: GetState) => ({
  createAccountGroup: (input: { name: string; ledgerId?: string }): string => {
    const id = newId('ag', { long: false });
    const ledgerId = input.ledgerId ?? 'personal';
    set((s) => ({
      accountGroups: [
        ...s.accountGroups,
        { id, ledgerId, name: input.name, color: null, sortOrder: s.accountGroups.length },
      ],
    }));
    syncMutation('createAccountGroup', { id, ledgerId, name: input.name });
    return id;
  },

  updateAccountGroup: (id: string, patch: { name?: string }): void => {
    set((s) => ({ accountGroups: s.accountGroups.map((g) => (g.id === id ? { ...g, ...patch } : g)) }));
    syncMutation('updateAccountGroup', { id, patch });
  },

  deleteAccountGroup: (id: string): void => {
    set((s) => ({
      accountGroups: s.accountGroups.filter((g) => g.id !== id),
      // accounts.group_id is SET NULL by the FK; mirror that optimistically.
      accounts: s.accounts.map((a) => (a.groupId === id ? { ...a, groupId: null, groupName: null } : a)),
    }));
    syncMutation('deleteAccountGroup', { id });
  },
});
