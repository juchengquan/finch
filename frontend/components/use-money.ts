'use client';

import { useMemo } from 'react';
import { useLedger } from '@/components/ledger-provider';
import { useCurrency } from '@/components/currency-provider';
import { useFinanceStore } from '@/lib/store';
import { convertAmount, fmtNative, fmtNativeShort } from '@/lib/data';
import { latestRateMap, convertViaRates } from '@/lib/fx';

// Amounts are stored in the active ledger's base currency. `useMoney` converts
// them into the user's chosen display currency and formats them. Conversion
// goes through the projected exchange_rates table (latest rate per currency,
// SGD-pivoted) and falls back to the static units-per-USD map only when the
// table has no row for a currency (pre-hydration / unseeded currency).
export function useMoney() {
  const { active } = useLedger();
  const { currency: display } = useCurrency();
  const rates = useFinanceStore((s) => s.exchangeRates);
  const base = active.base;

  const rateMap = useMemo(() => latestRateMap(rates), [rates]);
  const convert = (amount: number) => {
    if (base === display) return amount;
    const v = convertViaRates(amount, base, display, rateMap);
    return v != null ? v : convertAmount(amount, base, display);
  };

  return {
    display,
    base,
    fmt: (amount: number, opts?: { signed?: boolean }) => fmtNative(convert(amount), display, opts),
    short: (amount: number) => fmtNativeShort(convert(amount), display),
  };
}
