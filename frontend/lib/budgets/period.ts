// Period arithmetic for budgets. Pure functions — no DB dependency.
//
// Period IDs are the YYYY-MM-DD `from` date of the window. They sort
// chronologically by simple lex compare, so the caller can use ordinary
// `<` / `>` to ask "did this period end before that one?" without parsing.
//
// Windows are derived from `cycleWindow` in lib/select.ts so the rollover loop
// and `budgetProgress` see exactly the same period bounds — a single source of
// truth avoids the trap of computing different from/to pairs for the same
// budget on different code paths.

import { cycleWindow } from '@/lib/select';

export type Frequency = 'daily' | 'weekly' | 'biweekly' | 'monthly' | 'quarterly' | 'yearly';

const pad2 = (n: number) => String(n).padStart(2, '0');
const toYmd = (d: Date) => `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
const fromYmd = (s: string) => {
  const [y, m, d] = s.slice(0, 10).split('-').map(Number);
  return new Date(y, (m || 1) - 1, d || 1);
};
const addDays = (d: Date, n: number) => {
  const x = new Date(d);
  x.setDate(x.getDate() + n);
  return x;
};

/** Canonical period id for the period containing `date` under `frequency`.
 *  The `anchor` is the budget's `start_date` — periods step from there. */
export function periodOf(date: string, frequency: Frequency, anchor: string): string {
  return cycleWindow(frequency, anchor, date).from;
}

/** Inclusive YYYY-MM-DD bounds of the period named `period`. */
export function periodRange(period: string, frequency: Frequency, anchor: string): { from: string; to: string } {
  return cycleWindow(frequency, anchor, period);
}

/** The period immediately after `period` (chronologically). */
export function nextPeriod(period: string, frequency: Frequency, anchor: string): string {
  const { to } = periodRange(period, frequency, anchor);
  return periodOf(toYmd(addDays(fromYmd(to), 1)), frequency, anchor);
}

/** The period immediately before `period` (chronologically). */
export function prevPeriod(period: string, frequency: Frequency, anchor: string): string {
  const { from } = periodRange(period, frequency, anchor);
  return periodOf(toYmd(addDays(fromYmd(from), -1)), frequency, anchor);
}

/** Human-readable label for a period id — for UI headers. Accepts an
 *  optional `locale` so month/day formatting follows the active UI
 *  language (defaults to undefined, which uses the runtime's default). */
export function periodLabel(period: string, frequency: Frequency, anchor: string, locale?: string): string {
  const d = fromYmd(period);
  switch (frequency) {
    case 'daily':
      return d.toLocaleDateString(locale, { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
    case 'monthly':
      // Calendar-aligned monthly (anchor on day 1) → "April 2026".
      // Otherwise show the window range so the label matches what the user sees.
      if (fromYmd(anchor).getDate() === 1) {
        return d.toLocaleDateString(locale, { year: 'numeric', month: 'long' });
      }
      break;
    case 'quarterly': {
      // Calendar-aligned quarterly (anchor on a Q boundary) → "2026 Q2".
      const anchorD = fromYmd(anchor);
      if (anchorD.getDate() === 1 && anchorD.getMonth() % 3 === 0) {
        return `${d.getFullYear()} Q${Math.floor(d.getMonth() / 3) + 1}`;
      }
      break;
    }
    case 'yearly': {
      // Calendar-aligned yearly (anchor on Jan 1) → "2026".
      const anchorD = fromYmd(anchor);
      if (anchorD.getDate() === 1 && anchorD.getMonth() === 0) {
        return String(d.getFullYear());
      }
      break;
    }
    case 'weekly':
    case 'biweekly':
      break;
  }
  // Fallback: render the window range as a short label.
  const { to } = periodRange(period, frequency, anchor);
  const toD = fromYmd(to);
  const sameYear = d.getFullYear() === toD.getFullYear();
  const fmt = (x: Date, withYear: boolean) =>
    x.toLocaleDateString(locale, withYear
      ? { month: 'short', day: 'numeric', year: 'numeric' }
      : { month: 'short', day: 'numeric' });
  return `${fmt(d, !sameYear)} – ${fmt(toD, true)}`;
}
