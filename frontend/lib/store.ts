'use client';

import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import transactionsData from '@/data/transactions.json';
import pendingData from '@/data/pending.json';

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

const SEED_TX = transactionsData as Tx[];
const SEED_PENDING = pendingData as PendingItem[];

interface FinanceState {
  transactions: Tx[];
  pending: PendingItem[];
  addTransaction: (tx: Omit<Tx, 'id'>) => string;
  updateTransaction: (id: string, patch: Partial<Tx>) => void;
  deleteTransaction: (id: string) => void;
  confirmPending: (id: string) => void;
  cancelPending: (id: string) => void;
  confirmAllPending: () => void;
  reset: () => void;
}

export const useFinanceStore = create<FinanceState>()(
  persist(
    (set) => ({
      transactions: SEED_TX,
      pending: SEED_PENDING,

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

      reset: () => set({ transactions: SEED_TX, pending: SEED_PENDING }),
    }),
    {
      name: 'finch-store',
      version: 1,
      storage: createJSONStorage(() => localStorage),
      partialize: (s) => ({ transactions: s.transactions, pending: s.pending }),
      // SSR-safe: keep seed state on the server + first client render, then
      // rehydrate from localStorage after mount (see StoreHydration).
      skipHydration: true,
    },
  ),
);
