// frontend/lib/store/budgets/actions.ts — budget action creators.
// Extracted from lib/store.ts:706-808 (createBudget, updateBudget,
// updateBudgetCycle, clearPendingAmount, removeBudget,
// contributeBudget).
//
// `NewBudgetInput` is the client-side shape (booleans here, normalised
// to the DB's 0/1 ints on the way out).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';
import type { BudgetRow, BudgetType, BudgetPatch } from '@/lib/db/domain/budgets/types';

export interface NewBudgetInput {
  name: string;
  type: BudgetType;
  amount: number;
  groupId?: string | null;
  frequency?: string;
  startDate?: string;
  endDate?: string | null;
  isRecurring?: boolean;
  rollover?: boolean;
  rolloverLimit?: number | null;
  accountIds?: string[];
  categoryIds?: string[];
  tagIds?: string[];
  warningPct?: number;
  saved?: number;
  ledgerId?: string;
}

export const budgetActions = (set: SetState, get: GetState) => ({
  createBudget: (input: NewBudgetInput): string => {
    const id = newId('bgt', { long: false });
    const ledgerId = input.ledgerId ?? 'personal';
    const isRecurring = input.isRecurring != null ? (input.isRecurring ? 1 : 0) : input.type === 'income' ? 0 : 1;
    const row: BudgetRow = {
      id,
      ledgerId,
      groupId: input.groupId ?? null,
      name: input.name,
      type: input.type,
      amount: input.amount,
      saved: input.saved ?? 0,
      carryForward: 0,
      frequency: input.frequency ?? 'monthly',
      startDate: input.startDate ?? new Date().toISOString().slice(0, 10),
      endDate: input.endDate ?? null,
      isRecurring,
      rollover: input.rollover ? 1 : 0,
      rolloverLimit: input.rolloverLimit ?? null,
      pendingAmount: null,
      lastRolledPeriod: null,
      accountIds: input.accountIds ?? [],
      categoryIds: input.categoryIds ?? [],
      warningPct: input.warningPct ?? 80,
    };
    set((s) => ({ budgets: [...s.budgets, row] }));
    syncMutation('createBudget', {
      id,
      ledgerId,
      groupId: row.groupId,
      name: row.name,
      type: row.type,
      amount: row.amount,
      saved: row.saved,
      frequency: row.frequency,
      startDate: row.startDate,
      endDate: row.endDate,
      isRecurring: row.isRecurring,
      rollover: row.rollover,
      rolloverLimit: row.rolloverLimit,
      accountIds: row.accountIds,
      categoryIds: row.categoryIds,
      warningPct: row.warningPct,
    });
    return id;
  },

  updateBudget: (id: string, patch: BudgetPatch): void => {
    set((s) => ({
      budgets: s.budgets.map((b) => {
        if (b.id !== id) return b;
        // Mirror the server-side staging rule: amount-only patches on
        // recurring budgets write to pendingAmount, not amount.
        const keys = Object.keys(patch).filter(
          (k) => (patch as Record<string, unknown>)[k] !== undefined,
        );
        const amountOnly = keys.length === 1 && keys[0] === 'amount';
        if (amountOnly && b.isRecurring === 1) {
          return { ...b, pendingAmount: Number(patch.amount) };
        }
        return { ...b, ...patch };
      }),
    }));
    syncMutation('updateBudget', { id, patch });
  },

  updateBudgetCycle: (
    id: string,
    patch: { frequency: string; startDate: string; amount?: number; endDate?: string | null },
  ): void => {
    set((s) => ({
      budgets: s.budgets.map((b) => {
        if (b.id !== id) return b;
        const nextAmount = patch.amount ?? b.amount;
        return {
          ...b,
          amount: nextAmount,
          frequency: patch.frequency,
          startDate: patch.startDate,
          endDate: patch.endDate === undefined ? b.endDate : patch.endDate,
          pendingAmount: null,
          lastRolledPeriod: null,
        };
      }),
    }));
    syncMutation('updateBudgetCycle', { id, patch });
  },

  clearPendingAmount: (id: string): void => {
    set((s) => ({
      budgets: s.budgets.map((b) => (b.id === id ? { ...b, pendingAmount: null } : b)),
    }));
    syncMutation('clearPendingAmount', { id });
  },

  removeBudget: (id: string): void => {
    set((s) => ({ budgets: s.budgets.filter((b) => b.id !== id) }));
    syncMutation('removeBudget', { id });
  },

  contributeBudget: (id: string, amount: number): void => {
    set((s) => ({
      budgets: s.budgets.map((b) => (b.id === id ? { ...b, saved: Math.max(0, b.saved + amount) } : b)),
    }));
    syncMutation('contributeBudget', { id, amount });
  },
});
