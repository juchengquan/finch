// frontend/lib/store/rules/actions.ts — rules-engine action creators.
// Extracted from lib/store.ts:962-1006 (createRule, updateRule, deleteRule,
// backfillRule).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';
import type { Rule, Condition, Action } from '@/lib/rules/types';

export const ruleActions = (set: SetState, get: GetState) => ({
  createRule: (input: {
    name?: string | null;
    priority?: number;
    condition: Condition;
    actions: Action[];
    isActive?: boolean;
    runOnEdit?: boolean;
    ledgerId?: string;
  }): string => {
    const id = newId('rule', { long: false });
    const ledgerId = input.ledgerId ?? 'personal';
    const optimistic: Rule = {
      id,
      ledgerId,
      name: input.name ?? null,
      priority: input.priority ?? 100,
      condition: input.condition,
      actions: input.actions,
      isActive: input.isActive !== false,
      runOnEdit: input.runOnEdit === true,
      lastAppliedAt: null,
    };
    set((s) => ({ rules: [...s.rules, optimistic] }));
    syncMutation('createRule', {
      id,
      ledgerId,
      name: input.name ?? null,
      priority: optimistic.priority,
      condition: input.condition,
      actions: input.actions,
      isActive: optimistic.isActive,
      runOnEdit: optimistic.runOnEdit,
    });
    return id;
  },

  updateRule: (
    id: string,
    patch: {
      name?: string | null;
      priority?: number;
      condition?: Condition;
      actions?: Action[];
      isActive?: boolean;
      runOnEdit?: boolean;
    },
  ): void => {
    set((s) => ({
      rules: s.rules.map((r) => (r.id === id ? { ...r, ...patch, name: patch.name ?? r.name } : r)),
    }));
    syncMutation('updateRule', { id, patch });
  },

  deleteRule: (id: string): void => {
    set((s) => ({ rules: s.rules.filter((r) => r.id !== id) }));
    syncMutation('deleteRule', { id });
  },

  backfillRule: (id: string): void => {
    // No optimistic update — the server re-projection lands the patched
    // transactions + the rule's new last_applied_at on the round-trip.
    syncMutation('backfillRule', { id });
  },
});
