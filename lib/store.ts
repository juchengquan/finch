'use client';

import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import transactionsData from '@/data/transactions.json';
import pendingData from '@/data/pending.json';
import recurringData from '@/data/recurring-templates.json';

export interface Tx {
  id: string;
  merchant: string;
  category: string | null;
  amount: number;
  account: string;
  date: string;
  time?: string;
  note?: string;
  pending?: boolean;
  recurring?: boolean;
  kind?: string;
  ledgerId?: string;
}

export interface PendingItem {
  id: string;
  merchant: string;
  amount: number;
  currency: string;
  date: string;
  account: string;
  reason: string;
  source: string;
}

export interface RecurringSplit {
  account: string;
  pct: number;
  abs: number | null;
  label: string;
}

export interface RecurringTemplate {
  id: string;
  name: string;
  type: string;
  amount: number | null;
  varies?: number;
  frequency: string;
  dayOfMonth: number;
  account: string;
  from?: string;
  autoPost: number;
  nextRun: string;
  lastRun: string;
  splits?: RecurringSplit[];
}

const SEED_TX = transactionsData as Tx[];
const SEED_PENDING = pendingData as PendingItem[];
const SEED_RECURRING = recurringData as RecurringTemplate[];

interface FinanceState {
  transactions: Tx[];
  pending: PendingItem[];
  recurring: RecurringTemplate[];
  // Editable overrides on otherwise-static mock data, persisted.
  budgetOverrides: Record<string, number>;
  verifiedExtra: string[];
  aliasExtra: Record<string, string[]>;

  addTransaction: (tx: Omit<Tx, 'id'>) => string;
  updateTransaction: (id: string, patch: Partial<Tx>) => void;
  deleteTransaction: (id: string) => void;
  confirmPending: (id: string) => void;
  cancelPending: (id: string) => void;
  confirmAllPending: () => void;
  setBudget: (categoryId: string, amount: number) => void;
  updateRecurringSplit: (templateId: string, index: number, pct: number) => void;
  verifyCounterparty: (id: string) => void;
  addAlias: (id: string, alias: string) => void;
  reset: () => void;
}

export const useFinanceStore = create<FinanceState>()(
  persist(
    (set) => ({
      transactions: SEED_TX,
      pending: SEED_PENDING,
      recurring: SEED_RECURRING,
      budgetOverrides: {},
      verifiedExtra: [],
      aliasExtra: {},

      addTransaction: (tx) => {
        const id = `t-${Date.now().toString(36)}`;
        set((s) => ({ transactions: [{ ...tx, id }, ...s.transactions] }));
        return id;
      },

      updateTransaction: (id, patch) =>
        set((s) => ({
          transactions: s.transactions.map((t) => (t.id === id ? { ...t, ...patch } : t)),
        })),

      deleteTransaction: (id) =>
        set((s) => ({ transactions: s.transactions.filter((t) => t.id !== id) })),

      confirmPending: (id) => set((s) => ({ pending: s.pending.filter((p) => p.id !== id) })),

      cancelPending: (id) => set((s) => ({ pending: s.pending.filter((p) => p.id !== id) })),

      confirmAllPending: () => set({ pending: [] }),

      setBudget: (categoryId, amount) =>
        set((s) => ({ budgetOverrides: { ...s.budgetOverrides, [categoryId]: amount } })),

      updateRecurringSplit: (templateId, index, pct) =>
        set((s) => ({
          recurring: s.recurring.map((t) =>
            t.id === templateId && t.splits
              ? { ...t, splits: t.splits.map((sp, i) => (i === index ? { ...sp, pct } : sp)) }
              : t,
          ),
        })),

      verifyCounterparty: (id) =>
        set((s) => ({ verifiedExtra: s.verifiedExtra.includes(id) ? s.verifiedExtra : [...s.verifiedExtra, id] })),

      addAlias: (id, alias) =>
        set((s) => ({
          aliasExtra: { ...s.aliasExtra, [id]: [...(s.aliasExtra[id] ?? []), alias] },
        })),

      reset: () =>
        set({
          transactions: SEED_TX,
          pending: SEED_PENDING,
          recurring: SEED_RECURRING,
          budgetOverrides: {},
          verifiedExtra: [],
          aliasExtra: {},
        }),
    }),
    {
      name: 'finch-store',
      version: 1,
      storage: createJSONStorage(() => localStorage),
      partialize: (s) => ({
        transactions: s.transactions,
        pending: s.pending,
        recurring: s.recurring,
        budgetOverrides: s.budgetOverrides,
        verifiedExtra: s.verifiedExtra,
        aliasExtra: s.aliasExtra,
      }),
      // SSR-safe: keep seed state on the server + first client render, then
      // rehydrate from localStorage after mount (see StoreHydration).
      skipHydration: true,
    },
  ),
);
