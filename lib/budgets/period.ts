// Period arithmetic for budgets. Pure functions — no DB dependency. Period IDs
// are stable strings that sort chronologically by simple lex compare, so the
// caller can use ordinary `<` / `>` to ask "did this period end before that
// one?" without parsing.
//
// Canonical period-id formats:
//   daily      → YYYY-MM-DD              e.g. '2026-04-15'
//   weekly     → YYYY-Www                e.g. '2026-W16'   (ISO 8601 week)
//   biweekly   → BW-YYYY-MM-DD           e.g. 'BW-2026-04-13' (Monday of the
//                                        bucket's first week — anchored)
//   monthly    → YYYY-MM                 e.g. '2026-04'
//   quarterly  → YYYY-Qq                 e.g. '2026-Q2'
//   yearly     → YYYY                    e.g. '2026'
//
// Weekly uses ISO 8601 week numbering (Monday-first, weeks containing Jan 4
// belong to that year). The `anchor` argument (the budget's start_date) only
// matters for biweekly: it picks which of the two possible phasings the
// budget runs on. For every other cycle, anchor is ignored.

export type Frequency = 'daily' | 'weekly' | 'biweekly' | 'monthly' | 'quarterly' | 'yearly';

const pad2 = (n: number) => (n < 10 ? `0${n}` : String(n));
const DAY_MS = 24 * 3600 * 1000;

function asDate(date: string): Date {
  // Parse YYYY-MM-DD as a UTC date so day arithmetic doesn't shift across DST.
  const [y, m, d] = date.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

function ymd(d: Date): string {
  return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`;
}

// ISO 8601 week number + the ISO-week-numbering year for `date`. The two can
// differ from the calendar year for dates near a year boundary (Dec 31 might
// belong to ISO week 1 of the next year, and Jan 1 might belong to week 52 of
// the previous).
function isoWeek(date: Date): { isoYear: number; week: number } {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  // ISO weekday: Mon=1..Sun=7. UTC getDay() is Sun=0..Sat=6.
  const dayNr = (d.getUTCDay() + 6) % 7;
  // Thursday of the same ISO week — its calendar year IS the ISO-week year.
  d.setUTCDate(d.getUTCDate() - dayNr + 3);
  const isoYear = d.getUTCFullYear();
  const yearStartThursday = new Date(Date.UTC(isoYear, 0, 4));
  yearStartThursday.setUTCDate(yearStartThursday.getUTCDate() - ((yearStartThursday.getUTCDay() + 6) % 7) + 3);
  const week = 1 + Math.round((d.getTime() - yearStartThursday.getTime()) / (7 * DAY_MS));
  return { isoYear, week };
}

/** Monday (UTC) of the ISO week containing `date`. */
function isoWeekStart(date: Date): Date {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayNr = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - dayNr);
  return d;
}

/**
 * Canonical period id for the period containing `date` under `frequency`.
 * The `anchor` (the budget's start_date) only matters for biweekly.
 */
export function periodOf(date: string, frequency: Frequency, anchor: string): string {
  const d = asDate(date);
  switch (frequency) {
    case 'daily':
      return ymd(d);
    case 'weekly': {
      const { isoYear, week } = isoWeek(d);
      return `${isoYear}-W${pad2(week)}`;
    }
    case 'biweekly': {
      // Count whole ISO weeks from the anchor's Monday to date's Monday, then
      // bucket every two weeks together starting from the anchor. The bucket's
      // start (Monday of its first week) becomes the ID — sorts chronologically
      // by lex compare and round-trips with no parsing math.
      const aStart = isoWeekStart(asDate(anchor));
      const dStart = isoWeekStart(d);
      const weeks = Math.floor((dStart.getTime() - aStart.getTime()) / (7 * DAY_MS));
      const bucketStart = new Date(aStart);
      bucketStart.setUTCDate(bucketStart.getUTCDate() + Math.floor(weeks / 2) * 14);
      return `BW-${ymd(bucketStart)}`;
    }
    case 'monthly':
      return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}`;
    case 'quarterly':
      return `${d.getUTCFullYear()}-Q${Math.floor(d.getUTCMonth() / 3) + 1}`;
    case 'yearly':
      return String(d.getUTCFullYear());
  }
}

/** Inclusive YYYY-MM-DD bounds of the period named `period`. */
export function periodRange(period: string, frequency: Frequency): { from: string; to: string } {
  switch (frequency) {
    case 'daily':
      return { from: period, to: period };
    case 'weekly': {
      const [yStr, wStr] = period.split('-W');
      const isoYear = Number(yStr);
      const week = Number(wStr);
      // ISO week 1 contains the year's first Thursday → its Monday is the start.
      const jan4 = new Date(Date.UTC(isoYear, 0, 4));
      const dayNr = (jan4.getUTCDay() + 6) % 7;
      const w1Mon = new Date(jan4);
      w1Mon.setUTCDate(jan4.getUTCDate() - dayNr);
      const from = new Date(w1Mon);
      from.setUTCDate(from.getUTCDate() + (week - 1) * 7);
      const to = new Date(from);
      to.setUTCDate(to.getUTCDate() + 6);
      return { from: ymd(from), to: ymd(to) };
    }
    case 'biweekly': {
      // BW-<bucket-start>; the bucket starts on a Monday and spans 14 days.
      const startStr = period.slice(3);
      const from = asDate(startStr);
      const to = new Date(from);
      to.setUTCDate(to.getUTCDate() + 13);
      return { from: startStr, to: ymd(to) };
    }
    case 'monthly': {
      const [y, m] = period.split('-').map(Number);
      const from = new Date(Date.UTC(y, m - 1, 1));
      const to = new Date(Date.UTC(y, m, 0));
      return { from: ymd(from), to: ymd(to) };
    }
    case 'quarterly': {
      const [yStr, qStr] = period.split('-Q');
      const y = Number(yStr);
      const q = Number(qStr);
      const from = new Date(Date.UTC(y, (q - 1) * 3, 1));
      const to = new Date(Date.UTC(y, q * 3, 0));
      return { from: ymd(from), to: ymd(to) };
    }
    case 'yearly': {
      const y = Number(period);
      return { from: `${y}-01-01`, to: `${y}-12-31` };
    }
  }
}

/**
 * The period immediately after `period` (chronologically). `anchor` is the
 * budget's start_date — needed for biweekly so we land on the right phase.
 */
export function nextPeriod(period: string, frequency: Frequency, anchor: string): string {
  const { to } = periodRange(period, frequency);
  const after = asDate(to);
  after.setUTCDate(after.getUTCDate() + 1);
  return periodOf(ymd(after), frequency, anchor);
}

/** The period immediately before `period` (chronologically). */
export function prevPeriod(period: string, frequency: Frequency, anchor: string): string {
  const { from } = periodRange(period, frequency);
  const before = asDate(from);
  before.setUTCDate(before.getUTCDate() - 1);
  return periodOf(ymd(before), frequency, anchor);
}

const MONTH_NAMES = ['January','February','March','April','May','June','July','August','September','October','November','December'];

/** Human-readable label for a period id — for UI headers. */
export function periodLabel(period: string, frequency: Frequency): string {
  switch (frequency) {
    case 'daily':
      return new Date(`${period}T00:00:00Z`).toLocaleDateString('en-US', {
        weekday: 'short', month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC',
      });
    case 'weekly':
      return `Week ${period.slice(-2)} · ${period.slice(0, 4)}`;
    case 'biweekly': {
      const startStr = period.slice(3);
      const d = new Date(`${startStr}T00:00:00Z`);
      const label = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
      return `Biweek of ${label}`;
    }
    case 'monthly': {
      const [y, m] = period.split('-').map(Number);
      return `${MONTH_NAMES[m - 1]} ${y}`;
    }
    case 'quarterly':
      return period.replace('-', ' ');
    case 'yearly':
      return period;
  }
}
