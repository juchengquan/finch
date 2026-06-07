// PR A of plans/DOUBLE_ENTRY_PLAN.md §3: the single write chokepoint for the
// entries/postings double-entry core. Nothing outside this module (and the
// PR B migration) writes those tables. Every function assumes the caller
// holds the API route's BEGIN/COMMIT (lib/db/server.ts:392); multi-statement
// writes compose via SAVEPOINT, the recomputeAmountBases idiom.

import type { Exec } from '@/lib/db/repo';

const newId = (prefix: string) =>
  `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;

export type EntryKind = 'opening' | 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund';
export type EntryStatus = 'pending' | 'confirmed';

// --- System (equity) categories -------------------------------------------

const SYSTEM_CATEGORIES = [
  { system: 'opening', name: 'Opening balance' },
  { system: 'adjustment', name: 'Balance adjustment' },
  { system: 'fx', name: 'FX gain/loss' },
] as const;

export interface SystemCategoryIds {
  opening: string;
  adjustment: string;
  fx: string;
}

/** Idempotently seed the three equity system categories for a ledger and
 *  return their ids. Resolved by the `system` marker (rename-safe), never by
 *  id or name. Callers: tests now; seed / createLedger / migration in PR B. */
export async function ensureSystemCategories(exec: Exec, ledgerId: string): Promise<SystemCategoryIds> {
  const out: Record<string, string> = {};
  for (let i = 0; i < SYSTEM_CATEGORIES.length; i++) {
    const { system, name } = SYSTEM_CATEGORIES[i];
    const rows = await exec('SELECT id FROM categories WHERE ledger_id = ? AND system = ?', [ledgerId, system]);
    if (rows.length) {
      out[system] = String(rows[0].id);
      continue;
    }
    const id = newId('cat');
    await exec(
      `INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,system,created_at,updated_at)
       VALUES (?,?,NULL,?,'equity',NULL,NULL,?,?,datetime('now'),datetime('now'))`,
      [id, ledgerId, name, 9000 + i, system],
    );
    out[system] = id;
  }
  return out as unknown as SystemCategoryIds;
}
