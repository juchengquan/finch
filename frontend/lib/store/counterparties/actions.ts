// frontend/lib/store/counterparties/actions.ts — counterparty action creators.
// Extracted from lib/store.ts:863-871 (verifyCounterparty, unverifyCounterparty)
// + lib/store.ts:1059-1075 (createCounterparty, updateCounterparty,
// deleteCounterparty).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';

export const counterpartyActions = (set: SetState, get: GetState) => ({
  createCounterparty: (input: { name: string; ledgerId?: string }): string => {
    const id = newId('cp', { long: false });
    const ledgerId = input.ledgerId ?? 'personal';
    set((s) => ({ counterparties: [...s.counterparties, { id, ledgerId, name: input.name, verified: false }] }));
    syncMutation('createCounterparty', { id, ledgerId, name: input.name });
    return id;
  },

  updateCounterparty: (id: string, patch: { name?: string }): void => {
    set((s) => ({ counterparties: s.counterparties.map((c) => (c.id === id ? { ...c, ...patch } : c)) }));
    syncMutation('updateCounterparty', { id, patch });
  },

  deleteCounterparty: (id: string): void => {
    set((s) => ({ counterparties: s.counterparties.filter((c) => c.id !== id) }));
    syncMutation('deleteCounterparty', { id });
  },

  verifyCounterparty: (id: string): void => {
    set((s) => ({ counterparties: s.counterparties.map((c) => (c.id === id ? { ...c, verified: true } : c)) }));
    syncMutation('verifyCounterparty', { id });
  },

  unverifyCounterparty: (id: string): void => {
    set((s) => ({ counterparties: s.counterparties.map((c) => (c.id === id ? { ...c, verified: false } : c)) }));
    syncMutation('unverifyCounterparty', { id });
  },
});
