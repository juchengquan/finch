'use client';

import { create } from 'zustand';
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

// Editable fields on an otherwise-static MOCK account.
export interface AccountOverride {
  name?: string;
  type?: string;
  last4?: string;
  institution?: string;
  routing?: string;
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
  accountOverrides: Record<string, AccountOverride>;
  verifiedExtra: string[];
  aliasExtra: Record<string, string[]>;

  addTransaction: (tx: Omit<Tx, 'id'>) => string;
  updateTransaction: (id: string, patch: Partial<Tx>) => void;
  deleteTransaction: (id: string) => void;
  confirmPending: (id: string) => void;
  cancelPending: (id: string) => void;
  confirmAllPending: () => void;
  setBudget: (categoryId: string, amount: number) => void;
  setAccountDetails: (accountId: string, patch: AccountOverride) => void;
  updateRecurringSplit: (templateId: string, index: number, pct: number) => void;
  verifyCounterparty: (id: string) => void;
  addAlias: (id: string, alias: string) => void;
  reset: () => void;
}

// Persistence lives outside the store: lib/persistence.ts loads on startup and
// components/sqlite-backup-provider.tsx auto-saves to the SQLite `.db` (OPFS) —
// or localStorage when OPFS is unavailable — on every change. The store itself
// just starts from the seed data each render (SSR-safe), then gets hydrated.
export const useFinanceStore = create<FinanceState>()(
  (set) => ({
      transactions: SEED_TX,
      pending: SEED_PENDING,
      recurring: SEED_RECURRING,
      budgetOverrides: {},
      accountOverrides: {},
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

      setAccountDetails: (accountId, patch) =>
        set((s) => ({
          accountOverrides: {
            ...s.accountOverrides,
            [accountId]: { ...s.accountOverrides[accountId], ...patch },
          },
        })),

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
          accountOverrides: {},
          verifiedExtra: [],
          aliasExtra: {},
        }),
  }),
);
