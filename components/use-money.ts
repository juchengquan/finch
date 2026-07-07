'use client';

import { useMemo } from 'react';
import { useLedger } from '@/components/ledger-provider';
import { useCurrency } from '@/components/use-currency';
import { useFinanceStore } from '@/lib/store';
import { convertAmount, fmtNative, fmtNativeShort } from '@/lib/data';
import { latestRateMap, convertViaRates } from '@/lib/fx';
import { usePrivacy, MONEY_MASK } from '@/lib/use-privacy';

// Amounts are stored in the active ledger's base currency. `useMoney` converts
// them into the user's chosen display currency and formats them. Conversion
// goes through the projected exchange_rates table (latest rate per currency,
// USD-pivoted) and falls back to the static units-per-USD map only when the
// table has no row for a currency (pre-hydration / unseeded currency).
//
// Privacy mode masks every formatter here (fmt/short/fmtFrom/shortFrom and the
// own-currency native/nativeShort). Components must format personal amounts
// through this hook — calling lib/data's fmtNative directly bypasses the mask.
export function useMoney() {
  const { active } = useLedger();
  const { currency: display } = useCurrency();
  const { privacy } = usePrivacy();
  const rates = useFinanceStore((s) => s.exchangeRates);
  const base = active.base;

  const rateMap = useMemo(() => latestRateMap(rates), [rates]);
  // Convert between any two currencies via the projected rate map, with the
  // static map as a pre-hydration fallback so a value is always produced.
  const convertCur = (amount: number, from: string, to: string) => {
    if (from === to) return amount;
    const v = convertViaRates(amount, from, to, rateMap);
    return v != null ? v : convertAmount(amount, from, to);
  };
  const convert = (amount: number) => convertCur(amount, base, display);

  return {
    display,
    base,
    privacy,
    // Ledger-base → display (use for store/MOCK amounts already in the ledger base).
    fmt: (amount: number, opts?: { signed?: boolean }) =>
      privacy ? MONEY_MASK : fmtNative(convert(amount), display, opts),
    short: (amount: number) => (privacy ? MONEY_MASK : fmtNativeShort(convert(amount), display)),
    // Re-express an account-currency amount into the ledger base (for cross-account
    // sums like net worth) or into the display currency (for an "≈" secondary line).
    // Numeric — feeds further math, so privacy doesn't touch it.
    toBase: (amount: number, from: string) => convertCur(amount, from, base),
    fmtFrom: (amount: number, from: string, opts?: { signed?: boolean }) =>
      privacy ? MONEY_MASK : fmtNative(convertCur(amount, from, display), display, opts),
    shortFrom: (amount: number, from: string) =>
      privacy ? MONEY_MASK : fmtNativeShort(convertCur(amount, from, display), display),
    // An amount already denominated in its own currency — no conversion, just
    // format-or-mask. The privacy-aware replacement for calling fmtNative
    // directly in a component.
    native: (amount: number, currency: string, opts?: { signed?: boolean }) =>
      privacy ? MONEY_MASK : fmtNative(amount, currency, opts),
    nativeShort: (amount: number, currency: string) =>
      privacy ? MONEY_MASK : fmtNativeShort(amount, currency),
  };
}
