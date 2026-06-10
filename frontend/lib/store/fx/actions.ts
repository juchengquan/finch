// frontend/lib/store/fx/actions.ts — exchange-rate action creators.
// Extracted from lib/store.ts:1077-1091 (setExchangeRate, deleteExchangeRate).

import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';

export const fxActions = (set: SetState, get: GetState) => ({
  setExchangeRate: (input: { date: string; currency: string; rate: number; source?: string | null }): void => {
    const currency = input.currency.trim().toUpperCase();
    const source = input.source ?? null;
    set((s) => {
      const rest = s.exchangeRates.filter((r) => !(r.date === input.date && r.currency === currency));
      return { exchangeRates: [...rest, { date: input.date, currency, rate: input.rate, source }] };
    });
    syncMutation('setExchangeRate', { date: input.date, currency, rate: input.rate, source });
  },

  deleteExchangeRate: (date: string, currency: string): void => {
    const upper = currency.toUpperCase();
    set((s) => ({ exchangeRates: s.exchangeRates.filter((r) => !(r.date === date && r.currency === upper)) }));
    syncMutation('deleteExchangeRate', { date, currency: upper });
  },
});
