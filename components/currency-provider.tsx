'use client';

import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';

export type Currency = 'USD' | 'EUR' | 'GBP' | 'JPY' | 'SGD' | 'CNY';

// Display currency is per-ledger: the currency a ledger's amounts are converted
// to for viewing. The choice is persisted in the synced store (DB-backed), so it
// follows the user across devices. Until a ledger has an explicit choice, it
// shows its own base currency. Reads useLedger, so callers must be within
// LedgerProvider (all app content is).
export function useCurrency() {
  const { activeId, active } = useLedger();
  const byLedger = useFinanceStore((s) => s.displayCurrencyByLedger);
  const setDisplayCurrency = useFinanceStore((s) => s.setDisplayCurrency);

  const currency = (byLedger[activeId] ?? active.base) as Currency;
  const setCurrency = (c: Currency) => setDisplayCurrency(activeId, c);

  return { currency, setCurrency };
}
