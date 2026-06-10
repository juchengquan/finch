// frontend/lib/store/tags/actions.ts — tag action creators.
// Extracted from lib/store.ts:901-960 (createTag, updateTag, deleteTag).
//
// `setTransactionTags` is in `transactions/actions.ts` — it operates on
// the transactions slice even though it semantically assigns tags.

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';

export const tagActions = (set: SetState, get: GetState) => ({
  createTag: (input: { name: string; color?: string; ledgerId?: string }): string => {
    const ledgerId = input.ledgerId ?? 'personal';
    const id = newId('tag', { long: false });
    const color = input.color ?? null;
    set((s) => ({ tags: [...s.tags, { id, ledgerId, name: input.name, color }] }));
    syncMutation('createTag', { id, ledgerId, name: input.name, color });
    return id;
  },

  updateTag: (id: string, patch: { name?: string; color?: string | null }): void => {
    set((s) => ({ tags: s.tags.map((t) => (t.id === id ? { ...t, ...patch } : t)) }));
    syncMutation('updateTag', { id, patch });
  },

  deleteTag: (id: string): void => {
    set((s) => ({
      tags: s.tags.filter((t) => t.id !== id),
      transactions: s.transactions.map((t) => (t.tags ? { ...t, tags: t.tags.filter((x) => x !== id) } : t)),
    }));
    syncMutation('deleteTag', { id });
  },
});
