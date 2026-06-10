// frontend/lib/store/holdings/actions.ts — investment holdings action creators.
// Extracted from lib/store.ts:1096-1152 (createHolding, updateHolding,
// setHoldingPrice, deleteHolding).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';

export const holdingActions = (set: SetState, get: GetState) => ({
  createHolding: (input: {
    accountId: string;
    symbol: string;
    name?: string | null;
    shares: number;
    costBasis: number;
    currency?: string;
    lastPrice?: number | null;
    lastPriceDate?: string | null;
    notes?: string | null;
    ledgerId?: string;
  }): string => {
    const id = newId('h');
    const symbol = input.symbol.trim().toUpperCase();
    const ledgerId = input.ledgerId ?? 'personal';
    set((s) => ({
      holdings: [
        ...s.holdings,
        {
          id,
          ledgerId,
          accountId: input.accountId,
          symbol,
          name: input.name ?? null,
          shares: input.shares,
          costBasis: input.costBasis,
          currency: input.currency ?? 'USD',
          lastPrice: input.lastPrice ?? null,
          lastPriceDate: input.lastPriceDate ?? null,
          notes: input.notes ?? null,
        },
      ],
    }));
    syncMutation('createHolding', {
      id,
      ledgerId,
      accountId: input.accountId,
      symbol,
      name: input.name ?? null,
      shares: input.shares,
      costBasis: input.costBasis,
      currency: input.currency ?? null,
      lastPrice: input.lastPrice ?? null,
      lastPriceDate: input.lastPriceDate ?? null,
      notes: input.notes ?? null,
    });
    return id;
  },

  updateHolding: (
    id: string,
    patch: { symbol?: string; name?: string | null; shares?: number; costBasis?: number; notes?: string | null },
  ): void => {
    const normalized = patch.symbol == null ? patch : { ...patch, symbol: patch.symbol.trim().toUpperCase() };
    set((s) => ({
      holdings: s.holdings.map((h) => (h.id === id ? { ...h, ...normalized } : h)),
    }));
    syncMutation('updateHolding', { id, patch: normalized });
  },

  setHoldingPrice: (id: string, price: number | null, date: string | null): void => {
    set((s) => ({
      holdings: s.holdings.map((h) => (h.id === id ? { ...h, lastPrice: price, lastPriceDate: date } : h)),
    }));
    syncMutation('setHoldingPrice', { id, price, date });
  },

  deleteHolding: (id: string): void => {
    set((s) => ({ holdings: s.holdings.filter((h) => h.id !== id) }));
    syncMutation('deleteHolding', { id });
  },
});
