'use client';

// Locale-aware Intl wrappers. The format helpers in `lib/data.ts` are
// money-only and English-only by design; this hook is for *non*-money
// surfaces — dates on the activity feed, counts on chips, "3 days ago"
// strings on rule rows. Reads the active locale from `useAppLocale` so
// switching the picker reformats the whole UI on the next render.
//
// Each formatter is memoised on (locale, options) so the same row in a
// big list reuses one Intl instance, not a fresh one per call. We don't
// expose the Intl objects directly — callers pass the value + the option
// bag and get a string back.

import { useMemo } from 'react';
import { useAppLocale } from '@/components/i18n-provider';

export interface UseFormat {
  /** Format a Date or YYYY-MM-DD string. Defaults to medium date, no time. */
  fmtDate: (value: Date | string, options?: Intl.DateTimeFormatOptions) => string;
  /** Format a number. Defaults to no decimals; pass `{ maximumFractionDigits }` to widen. */
  fmtNumber: (value: number, options?: Intl.NumberFormatOptions) => string;
  /** "3 days ago" / "in 2 weeks". Pass a Date or epoch ms; the unit is auto-picked
   *  from the magnitude (minute / hour / day / week / month / year). */
  fmtRelative: (value: Date | number, options?: Intl.RelativeTimeFormatOptions) => string;
}

const DEFAULT_DATE: Intl.DateTimeFormatOptions = { year: 'numeric', month: 'short', day: 'numeric' };

function toDate(value: Date | string): Date {
  if (value instanceof Date) return value;
  // YYYY-MM-DD parsed as local date (not UTC) so the calendar day matches the
  // user's clock — `new Date('2026-06-07')` is UTC midnight and slides a day
  // earlier in the Americas.
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return new Date(value);
}

const RELATIVE_UNITS: { unit: Intl.RelativeTimeFormatUnit; ms: number }[] = [
  { unit: 'year', ms: 365 * 24 * 60 * 60 * 1000 },
  { unit: 'month', ms: 30 * 24 * 60 * 60 * 1000 },
  { unit: 'week', ms: 7 * 24 * 60 * 60 * 1000 },
  { unit: 'day', ms: 24 * 60 * 60 * 1000 },
  { unit: 'hour', ms: 60 * 60 * 1000 },
  { unit: 'minute', ms: 60 * 1000 },
];

export function useFormat(): UseFormat {
  const { locale } = useAppLocale();

  return useMemo<UseFormat>(() => {
    const dateCache = new Map<string, Intl.DateTimeFormat>();
    const numberCache = new Map<string, Intl.NumberFormat>();
    const relativeCache = new Map<string, Intl.RelativeTimeFormat>();
    const getDate = (opts: Intl.DateTimeFormatOptions) => {
      const key = JSON.stringify(opts);
      let v = dateCache.get(key);
      if (!v) { v = new Intl.DateTimeFormat(locale, opts); dateCache.set(key, v); }
      return v;
    };
    const getNumber = (opts: Intl.NumberFormatOptions) => {
      const key = JSON.stringify(opts);
      let v = numberCache.get(key);
      if (!v) { v = new Intl.NumberFormat(locale, opts); numberCache.set(key, v); }
      return v;
    };
    const getRelative = (opts: Intl.RelativeTimeFormatOptions) => {
      const key = JSON.stringify(opts);
      let v = relativeCache.get(key);
      if (!v) { v = new Intl.RelativeTimeFormat(locale, opts); relativeCache.set(key, v); }
      return v;
    };

    return {
      fmtDate: (value, options) => getDate(options ?? DEFAULT_DATE).format(toDate(value)),
      fmtNumber: (value, options) => getNumber(options ?? {}).format(value),
      fmtRelative: (value, options) => {
        const when = value instanceof Date ? value.getTime() : value;
        const diffMs = when - Date.now();
        const abs = Math.abs(diffMs);
        const match = RELATIVE_UNITS.find((u) => abs >= u.ms) ?? { unit: 'second' as const, ms: 1000 };
        const rounded = Math.round(diffMs / match.ms);
        return getRelative(options ?? { numeric: 'auto' }).format(rounded, match.unit);
      },
    };
  }, [locale]);
}
