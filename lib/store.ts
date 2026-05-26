'use client';

import { create } from 'zustand';
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

interface FinanceState {
  transactions: Tx[];
  pending: PendingItem[];
  addTransaction: (tx: Omit<Tx, 'id'>) => string;
  updateTransaction: (id: string, patch: Partial<Tx>) => void;
  deleteTransaction: (id: string) => void;
  confirmPending: (id: string) => void;
  cancelPending: (id: string) => void;
  confirmAllPending: () => void;
}

export const useFinanceStore = create<FinanceState>((set) => ({
  transactions: transactionsData as Tx[],
  pending: pendingData as PendingItem[],

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
}));
