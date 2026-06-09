// lib/db/domain/_shared/tx-touches.ts — capture a transaction's date and
// every category/account it touches, so mutation cases can feed
// invalidateRollover() with the before/after state of an edit. Now
// entries-based (B3b) — resolves the entry ref first, then reads the
// postings.
import { resolveEntryRef } from '../../core/entries';
import type { Exec } from '../../core/repo';

type Touches = { date: string; accountId: string; categoryIds: string[] };

export async function txTouches(exec: Exec, id: string): Promise<Touches | null> {
  const ref = await resolveEntryRef(exec, id);
  if (!ref) return null;
  const { entryId } = ref;
  const [e] = await exec('SELECT date FROM entries WHERE id = ?', [entryId]);
  if (!e) return null;
  const postings = await exec(
    'SELECT account_id, category_id FROM postings WHERE entry_id = ?',
    [entryId],
  );
  const categoryIds = new Set<string>();
  let accountId: string | null = null;
  for (const p of postings) {
    if (p.account_id != null && accountId == null) accountId = String(p.account_id);
    if (p.category_id != null) categoryIds.add(String(p.category_id));
  }
  if (!accountId) return null;
  return { date: String(e.date), accountId, categoryIds: [...categoryIds] };
}

export function mergeTouches(
  a: Touches | null,
  b: Touches | null,
): { earliestDate: string; categoryIds: string[]; accountIds: string[] } | null {
  if (!a && !b) return null;
  const dates = [a?.date, b?.date].filter((d): d is string => Boolean(d));
  const earliestDate = dates.sort()[0];
  const cats = new Set<string>([...(a?.categoryIds ?? []), ...(b?.categoryIds ?? [])]);
  const accts = new Set<string>([...(a ? [a.accountId] : []), ...(b ? [b.accountId] : [])]);
  return { earliestDate, categoryIds: [...cats], accountIds: [...accts] };
}
