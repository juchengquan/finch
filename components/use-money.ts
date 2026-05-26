'use client';

import { useLedger } from '@/components/ledger-provider';
import { useCurrency } from '@/components/currency-provider';
import { convertAmount, fmtNative, fmtNativeShort } from '@/lib/data';

// Amounts are stored in the active ledger's base currency. `useMoney` converts
// them into the user's chosen display currency and formats them.
export function useMoney() {
  const { active } = useLedger();
  const { currency: display } = useCurrency();
  const base = active.base;

  return {
    display,
    base,
    fmt: (amount: number, opts?: { signed?: boolean }) =>
      fmtNative(convertAmount(amount, base, display), display, opts),
    short: (amount: number) => fmtNativeShort(convertAmount(amount, base, display), display),
  };
}
