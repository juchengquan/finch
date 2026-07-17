// frontend/lib/store/budgetGroups/actions.ts — budget group action creators.
// Extracted from lib/store.ts:810-832 (createBudgetGroup, updateBudgetGroup,
// deleteBudgetGroup).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';

export const budgetGroupActions = (set: SetState, get: GetState) => ({
  createBudgetGroup: (input: { name: string; ledgerId?: string }): string => {
    const id = newId('bgg', { long: false });
    const ledgerId = input.ledgerId ?? 'personal';
    set((s) => ({
      budgetGroups: [...s.budgetGroups, { id, ledgerId, name: input.name, color: null, sortOrder: s.budgetGroups.length }],
    }));
    syncMutation('createBudgetGroup', { id, ledgerId, name: input.name });
    return id;
  },

  updateBudgetGroup: (id: string, patch: { name?: string }): void => {
    set((s) => ({ budgetGroups: s.budgetGroups.map((g) => (g.id === id ? { ...g, ...patch } : g)) }));
    syncMutation('updateBudgetGroup', { id, patch });
  },

  deleteBudgetGroup: (id: string): void => {
    set((s) => ({
      budgetGroups: s.budgetGroups.filter((g) => g.id !== id),
      // budgets.group_id is SET NULL by the FK; mirror that optimistically.
      budgets: s.budgets.map((b) => (b.groupId === id ? { ...b, groupId: null } : b)),
    }));
    syncMutation('deleteBudgetGroup', { id });
  },
});
