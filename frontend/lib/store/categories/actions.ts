// frontend/lib/store/categories/actions.ts — category action creators.
// Extracted from lib/store.ts:880-899 (createCategory, updateCategory,
// deleteCategory).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';

export const categoryActions = (set: SetState, get: GetState) => ({
  createCategory: (input: {
    name: string;
    type?: string;
    icon?: string;
    color?: string;
    parentId?: string | null;
    ledgerId?: string;
  }): void => {
    const ledgerId = input.ledgerId ?? 'personal';
    const id = newId('cat', { long: false });
    const type = input.type ?? 'expense';
    const icon = input.icon ?? null;
    const color = input.color ?? null;
    const parentId = input.parentId ?? null;
    set((s) => ({ categories: [...s.categories, { id, ledgerId, parentId, name: input.name, type, icon, color }] }));
    syncMutation('createCategory', { ledgerId, parentId, name: input.name, type, icon, color });
  },

  updateCategory: (
    id: string,
    patch: { name?: string; type?: string; icon?: string | null; color?: string | null; parentId?: string | null },
  ): void => {
    set((s) => ({ categories: s.categories.map((c) => (c.id === id ? { ...c, ...patch } : c)) }));
    syncMutation('updateCategory', { id, patch });
  },

  deleteCategory: (id: string): void => {
    set((s) => ({ categories: s.categories.filter((c) => c.id !== id) }));
    syncMutation('deleteCategory', { id });
  },
});
