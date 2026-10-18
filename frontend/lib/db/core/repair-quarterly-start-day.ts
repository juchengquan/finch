// Carry quarterly and yearly schedules on from the day they actually ran — the
// data half of #817, run as the 2026-10-19 migration (schema.ts).
//
// Until #817 a quarterly or yearly template recurred on its stored day_of_month,
// and the iOS sheet never sent one for those frequencies, so they all stored 1: a
// template starting 15 Mar came due on 1 Jun, 1 Sep… and users posted against those
// dates. #817 moved the recurrence onto the start date's day (15 Mar, 15 Jun, 15
// Sep), which is right for a new template but leaves an old one's history on dates
// the schedule no longer has — and generateDueScheduled, run on every load, books
// 15 Mar, 15 Jun and 15 Sep again.
//
// So, for such a template, the start moves to the first occurrence the OLD rule
// produced (1 Jun) and day_of_month to its day. The new rule then yields exactly the
// dates already posted. The end date stays; the caps count posted entries, not
// dates, so an installment plan or max_executions has the same number left; and the
// native skips (app_state.scheduledSkips) are keyed by occurrence date, which are
// occurrences again.
//
// Touched only when the history says so: a stored day that differs from the
// start's, and more posted or skipped dates on the old series than on the new one.
// A template starting on the 1st, one with no history, and one already used under
// the new rule are left alone; a second run finds the day and the start agreeing.
//
// A stored day of 29–31 makes the old rule clamp in short months, which a start date
// cannot say (a start on 30 Jun recurs on the 30th). There the start goes to the
// first old occurrence on the stored day itself, provided every one before it was
// posted or skipped, and otherwise to the first one, accepting the shorter day.
//
// Mirrors FinchCore's `Migrations.repairQuarterlyStartDays`.

import type { Exec } from './repo';
import type { ScheduledTemplate } from '@/lib/store';
import { occurrencesUpTo } from '@/lib/recurrence';

const isYMD = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s);
const pad = (n: number, w = 2) => String(n).padStart(w, '0');
const daysIn = (y: number, m: number) => new Date(Date.UTC(y, m, 0)).getUTCDate(); // m is 1-based

/** The pre-#817 recurrence for quarterly and yearly templates: whole steps of
 *  months from the start's month, each on `day` (clamped to the month's length),
 *  from the start through `through`, bounded by the end date. */
export function legacyMonthStepOccurrences(
  start: string, day: number, stepMonths: number, endDate: string | null, through: string,
): string[] {
  const end = endDate ? endDate.slice(0, 10) : null;
  const limit = end && isYMD(end) && end < through ? end : through;
  let y = Number(start.slice(0, 4));
  let m = Number(start.slice(5, 7));
  const out: string[] = [];
  for (let i = 0; i < 1200; i++) {
    const d = `${pad(y, 4)}-${pad(m)}-${pad(Math.min(day, daysIn(y, m)))}`;
    if (d > limit) break;
    if (d >= start) out.push(d);
    m += stepMonths;
    while (m > 12) {
      m -= 12;
      y += 1;
    }
  }
  return out;
}

async function loadSkips(exec: Exec): Promise<Record<string, string[]>> {
  try {
    const [row] = await exec(`SELECT value FROM app_state WHERE key = 'scheduledSkips'`);
    const map = row?.value == null ? null : JSON.parse(String(row.value));
    return map && typeof map === 'object' ? (map as Record<string, string[]>) : {};
  } catch {
    // No app_state table (a partial migrate fixture), or an unreadable value: no skips.
    return {};
  }
}

export async function repairQuarterlyStartDays(exec: Exec): Promise<void> {
  // Tolerate a partial database, the way the other data migrations do: migrate()
  // is exercised against minimal fixtures carrying only the tables they touch.
  const present = await exec(
    `SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('scheduled_templates','entries')`,
  );
  if (present.length < 2) return;
  const skips = await loadSkips(exec);
  const rows = await exec(
    `SELECT id, frequency, day_of_month, start_date, end_date FROM scheduled_templates
      WHERE frequency IN ('quarterly','yearly')`,
  );
  for (const r of rows) {
    const id = String(r.id);
    const rawStart = String(r.start_date ?? '');
    const start = rawStart.slice(0, 10);
    if (!isYMD(start)) continue;
    const startDay = Number(start.slice(8, 10));
    // The old rule read NULL as 1 and 0 as "the start's day".
    const stored = r.day_of_month == null ? 1 : Number(r.day_of_month);
    const oldDay = stored === 0 ? startDay : stored;
    if (oldDay === startDay || !(oldDay >= 1)) continue;

    const posted = await exec(
      'SELECT COALESCE(occurrence_date, date) AS d FROM entries WHERE source_template_id = ?',
      [id],
    );
    const history = new Set([...posted.map((p) => String(p.d)), ...(skips[id] ?? [])]);
    if (history.size === 0) continue;
    const through = [...history].sort().at(-1)!;

    const frequency = String(r.frequency);
    const endDate = r.end_date == null ? null : String(r.end_date);
    const old = legacyMonthStepOccurrences(start, oldDay, frequency === 'quarterly' ? 3 : 12, endDate, through);
    const current = new Set(occurrencesUpTo(
      { startDate: start, endDate, frequency, dayOfMonth: stored, nextRun: '' } as ScheduledTemplate,
      through,
    ));
    const oldSet = new Set(old);
    const onOld = [...history].filter((d) => oldSet.has(d) && !current.has(d)).length;
    const onNew = [...history].filter((d) => current.has(d) && !oldSet.has(d)).length;
    if (onOld <= onNew || old.length === 0) continue;

    let anchor = old[0];
    const i = old.findIndex((d) => Number(d.slice(8, 10)) === oldDay);
    if (i >= 0 && old.slice(0, i).every((d) => history.has(d))) anchor = old[i];
    // Keep anything after the day (the web form stores "YYYY-MM-DDTHH:mm").
    await exec(
      `UPDATE scheduled_templates SET start_date = ?, day_of_month = ?, updated_at = datetime('now')
        WHERE id = ?`,
      [anchor + rawStart.slice(10), Number(anchor.slice(8, 10)), id],
    );
  }
}
