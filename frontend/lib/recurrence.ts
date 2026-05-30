// Pure occurrence-date math for scheduled templates, shared by the server-side
// generator (lib/db/mutations.ts) and available to the calendar. Dates are
// computed in UTC and returned as 'YYYY-MM-DD' strings.

import type { ScheduledTemplate } from '@/lib/store';

const MS_DAY = 86_400_000;
const isISO = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s);
const toUTC = (iso: string) => {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  return Date.UTC(y, m - 1, d);
};
const fmt = (ms: number) => {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
};
const daysInMonth = (y: number, m: number) => new Date(Date.UTC(y, m + 1, 0)).getUTCDate();

/**
 * All occurrence dates for a template from its start through `throughInclusive`
 * (a 'YYYY-MM-DD' date, normally today), bounded by `endDate`. The template's
 * `startDate` anchors the series; `nextRun` is a fallback anchor. Returns [] when
 * there is no valid anchor. Callers handle dedup (vs. already-generated rows) and
 * `maxExecutions` capping.
 */
export function occurrencesUpTo(t: ScheduledTemplate, throughInclusive: string): string[] {
  const anchorIso = (t.startDate ?? t.nextRun ?? '').slice(0, 10);
  if (!isISO(anchorIso) || !isISO(throughInclusive)) return [];
  const start = toUTC(anchorIso);
  const endIso = t.endDate ? t.endDate.slice(0, 10) : null;
  const throughIso = endIso && isISO(endIso) && endIso < throughInclusive ? endIso : throughInclusive;
  const limit = toUTC(throughIso);
  if (start > limit) return [];

  const freq = t.frequency;
  if (freq === 'once') return [fmt(start)];

  const out: string[] = [];
  if (freq === 'daily' || freq === 'weekly' || freq === 'biweekly') {
    const step = (freq === 'daily' ? 1 : freq === 'weekly' ? 7 : 14) * MS_DAY;
    let cur = start;
    // Honor a fixed weekday for weekly/biweekly by advancing to the first match.
    if ((freq === 'weekly' || freq === 'biweekly') && t.weekDay != null) {
      let guard = 0;
      while (new Date(cur).getUTCDay() !== t.weekDay && guard++ < 7) cur += MS_DAY;
    }
    let guard = 0;
    while (cur <= limit && guard++ < 4000) {
      out.push(fmt(cur));
      cur += step;
    }
    return out;
  }

  // monthly / quarterly / yearly: step whole months, landing on dayOfMonth.
  const stepMonths = freq === 'quarterly' ? 3 : freq === 'yearly' ? 12 : 1;
  const day = t.dayOfMonth || new Date(start).getUTCDate();
  let y = new Date(start).getUTCFullYear();
  let m = new Date(start).getUTCMonth();
  let guard = 0;
  while (guard++ < 1200) {
    const ms = Date.UTC(y, m, Math.min(day, daysInMonth(y, m)));
    if (ms > limit) break;
    if (ms >= start) out.push(fmt(ms));
    m += stepMonths;
    while (m > 11) {
      m -= 12;
      y += 1;
    }
  }
  return out;
}
