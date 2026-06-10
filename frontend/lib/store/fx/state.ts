// frontend/lib/store/fx/state.ts — fx (exchange-rates) domain slice of
// the initial state. Pure data; the action creators (added in Task 4)
// live in fx/actions.ts.

import type { ExchangeRate } from '@/lib/db/domain/_app/system.types';

export const fxInitial = {
  exchangeRates: [] as ExchangeRate[],
} as const;
