// frontend/lib/store/transactions/actions.ts — transaction action creators.
// Extracted from lib/store.ts:470-647 (the bulk of the original actions).
// Also owns the two attachment actions (uploadAttachment, removeAttachment)
// from lib/store.ts:554-575 — the attachments state is just a slice of
// `state.attachments`, but the action creators live with the transactions
// domain because every attachment is bound to a transaction.
//
// Inlined store references like `useFinanceStore.getState()` are
// translated to the factory's `get()` parameter; `useFinanceStore.setState(state)`
// is translated to `set(state, true)` (replace mode — zustand v5).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';
import type { Tx, TxSplit, TxSplitInput } from './state';

export const transactionActions = (set: SetState, get: GetState) => ({
  addTransaction: (tx: Omit<Tx, 'id'> & { counterpartyId?: string | null }): string => {
    const id = newId('t', { long: false });
    set((s) => ({ transactions: [{ ...tx, id }, ...s.transactions] }));
    syncMutation('addTransaction', {
      ledgerId: tx.ledgerId ?? 'personal',
      accountId: tx.account,
      // `amount` is native (what the user entered); `amountBase` drives balances.
      amount: tx.nativeAmount ?? tx.amount,
      amountBase: tx.amount,
      currency: tx.currency,
      merchant: tx.merchant,
      categoryId: tx.category,
      date: tx.date,
      time: tx.time,
      note: tx.note,
      status: tx.pending ? 'pending' : 'confirmed',
      kind: tx.kind,
      refundedTransactionId: tx.refundedTransactionId,
      // Optional explicit counterparty link; the server's addTransaction
      // is a thin wrapper around insertTxRow which resolves the link
      // (auto-resolve by name, or accepts an explicit counterpartyId).
      counterpartyId: tx.counterpartyId ?? null,
    });
    return id;
  },

  adjustAccountBalance: (accountId: string, targetBalance: number, note?: string): void => {
    // The server rewrites/inserts the delta + recomputes; adopt the re-projection.
    syncMutation('adjustAccountBalance', { accountId, targetBalance, note });
  },

  updateTransaction: (id: string, patch: Partial<Tx>): void => {
    set((s) => ({
      transactions: s.transactions.map((t) => (t.id === id ? { ...t, ...patch } : t)),
    }));
    syncMutation('updateTransaction', { id, patch });
  },

  bulkRecategorize: (ids: string[], categoryId: string | null): void => {
    if (!ids.length) return;
    const idSet = new Set(ids);
    set((s) => ({
      transactions: s.transactions.map((t) => (idSet.has(t.id) ? { ...t, category: categoryId } : t)),
    }));
    syncMutation('bulkRecategorize', { ids, categoryId });
  },

  setCleared: (transactionId: string, cleared: boolean): void => {
    // Optimistic flip. Persist the same ISO timestamp the server would set
    // so the UI's clearedBalance line stays consistent until the projection
    // round-trip overwrites it.
    const stamp = cleared ? new Date().toISOString() : null;
    set((s) => ({
      transactions: s.transactions.map((t) =>
        t.id === transactionId ? { ...t, clearedAt: stamp } : t,
      ),
    }));
    syncMutation('setCleared', { id: transactionId, cleared });
  },

  setReviewed: (transactionId: string, reviewed: boolean): void => {
    const stamp = reviewed ? new Date().toISOString() : null;
    set((s) => ({
      transactions: s.transactions.map((t) =>
        t.id === transactionId ? { ...t, reviewedAt: stamp } : t,
      ),
    }));
    syncMutation('setReviewed', { id: transactionId, reviewed });
  },

  markAllReviewed: (ledgerId: string, opts?: { accountId?: string }): void => {
    const accountId = opts?.accountId;
    const stamp = new Date().toISOString();
    set((s) => ({
      transactions: s.transactions.map((t) => {
        if ((t.ledgerId ?? 'personal') !== ledgerId) return t;
        if (accountId && t.account !== accountId) return t;
        if (t.pending || t.reviewedAt) return t;
        return { ...t, reviewedAt: stamp };
      }),
    }));
    syncMutation('markAllReviewed', { ledgerId, accountId });
  },

  uploadAttachment: async (transactionId: string, file: File): Promise<string> => {
    // Upload bypasses syncMutation (multipart body, not JSON). The route
    // returns the same ProjectedState shape, so adoption mirrors the
    // syncMutation path. We let the caller catch errors so the UI can
    // surface them (size cap, mime allowlist, etc.).
    const { uploadAttachment } = await import('@/lib/api-client');
    const state = await uploadAttachment(transactionId, file);
    set(state, true);
    // The new row is the most recent one for this transaction.
    const created = [...state.attachments]
      .filter((a) => a.transactionId === transactionId)
      .sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1))[0];
    return created?.id ?? '';
  },

  removeAttachment: (id: string): void => {
    // Optimistic — drop the projected row immediately; the server
    // round-trip overwrites the slice with the authoritative state
    // (and unlinks the file).
    set((s) => ({ attachments: s.attachments.filter((a) => a.id !== id) }));
    syncMutation('removeAttachment', { id });
  },

  reconcileAccount: ({ accountId, statementBalance, statementDate, postAdjustment }: {
    accountId: string;
    statementBalance: number;
    statementDate: string;
    postAdjustment: boolean;
  }): void => {
    // Optimistic checkpoint stamp; the remainder Adjustment + cleared
    // flips on it arrive on the round-trip (we don't try to mirror the
    // SUM-and-post logic client-side — it's all in the server case).
    set((s) => ({
      accounts: s.accounts.map((a) =>
        a.id === accountId
          ? { ...a, lastReconciledAt: statementDate, lastReconciledBalance: statementBalance }
          : a,
      ),
    }));
    syncMutation('reconcileAccount', { accountId, statementBalance, statementDate, postAdjustment });
  },

  deleteTransaction: (id: string): void => {
    set((s) => ({ transactions: s.transactions.filter((t) => t.id !== id) }));
    syncMutation('deleteTransaction', { id });
  },

  // Pending items are transactions with status='pending'. Confirming flips the
  // status (flowing into reports/balances); cancelling voids the transaction.
  confirmPending: (id: string): void => {
    set((s) => ({ transactions: s.transactions.map((t) => (t.id === id ? { ...t, pending: false } : t)) }));
    syncMutation('confirmTransaction', { id });
  },

  confirmPendingWithMatch: (
    id: string,
    resolution: { kind: 'existing'; id: string } | { kind: 'new'; name: string } | { kind: 'skip' },
  ): void => {
    // Optimistically flip status. The server-side `confirmPendingWithMerchant`
    // mutation handles status flip + counterparty link + description rewrite
    // in a single UPDATE. We patch the local row's counterpartyId + merchant
    // so the UI doesn't wait for the round-trip to render the canonical name.
    set((s) => ({
      transactions: s.transactions.map((t) => {
        if (t.id !== id) return t;
        // Optimistic preview: if we know the canonical name, surface it
        // immediately. The server re-projects and replaces this with the
        // authoritative row.
        const patched: Tx = { ...t, pending: false };
        if (resolution.kind === 'existing') {
          const cp = get().counterparties.find((c) => c.id === resolution.id);
          if (cp) {
            patched.counterpartyId = cp.id;
            patched.merchant = cp.name;
          } else {
            patched.counterpartyId = resolution.id;
          }
        } else if (resolution.kind === 'new') {
          // Don't fabricate an id — leave the FK unset optimistically.
          // The server creates the counterparty and the projected state
          // surfaces the link.
          patched.merchant = resolution.name;
        }
        return patched;
      }),
    }));
    syncMutation('confirmPendingWithMerchant', {
      id,
      counterpartyId: resolution.kind === 'existing' ? resolution.id : null,
      newCounterpartyName: resolution.kind === 'new' ? resolution.name : null,
    });
  },

  cancelPending: (id: string): void => {
    set((s) => ({ transactions: s.transactions.filter((t) => t.id !== id) }));
    syncMutation('deleteTransaction', { id });
  },

  confirmAllPending: (): void => {
    set((s) => ({ transactions: s.transactions.map((t) => (t.pending ? { ...t, pending: false } : t)) }));
    syncMutation('confirmAllPending');
  },

  setTransactionTags: (transactionId: string, tagIds: string[]): void => {
    set((s) => ({
      transactions: s.transactions.map((t) => (t.id === transactionId ? { ...t, tags: tagIds } : t)),
    }));
    syncMutation('setTransactionTags', { id: transactionId, tagIds });
  },

  setTransactionSplits: (transactionId: string, splits: TxSplitInput[]): void => {
    set((s) => ({
      transactions: s.transactions.map((t) => {
        if (t.id !== transactionId) return t;
        if (!splits.length) {
          const { splits: _drop, ...rest } = t;
          void _drop;
          return rest;
        }
        const ratio = t.amount !== 0 && t.nativeAmount != null && t.nativeAmount !== 0
          ? t.amount / t.nativeAmount
          : 1;
        const optimistic: TxSplit[] = splits.map((sp, i) => ({
          id: `${transactionId}-s-${i}`,
          categoryId: sp.categoryId,
          amount: sp.amount,
          amountBase: Math.round(sp.amount * ratio * 100) / 100,
          description: sp.description ?? null,
        }));
        return { ...t, splits: optimistic };
      }),
    }));
    syncMutation('setTransactionSplits', {
      id: transactionId,
      splits: splits.map((s) => ({
        categoryId: s.categoryId,
        amount: s.amount,
        description: s.description ?? null,
      })),
    });
  },
});
