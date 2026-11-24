// What a rule may still write once the things it names have moved on.
//
// A rule stores ids — the category it sets, the merchant, the tags it adds, the
// categories of a split — and nothing stops those rows from being deleted
// afterwards. The engine used to write such an id straight into a posting or entry,
// so the FOREIGN KEY check refused the whole write: after deleting a category a
// rule pointed at, every matching transaction failed to save. Mirrors FinchCore's
// `RuleRefs` (ios/FinchCore/Sources/FinchCore/Rules/RuleRefs.swift).
import type { Exec } from './repo';
import type { RulePatch } from '@/lib/rules/types';

/** The kinds a rule may give an entry — the set `postEntry` lets a rule choose
 *  between. "transfer" or "adjustment" describes an entry with a different number
 *  of legs, which no rule can conjure; writing it anyway failed the ledger audit on
 *  every backup taken afterwards. */
export const RULED_KINDS: readonly string[] = ['income', 'expense', 'refund'];

/** Drop from `patch` every id that no longer names a row this ledger can use: a
 *  category or tag of this ledger, a merchant (merchants are global). A split with
 *  any dangling category is dropped whole — re-dividing it would invent a
 *  proportion the rule never asked for. The rule's other actions still apply. */
export async function pruneRulePatch(exec: Exec, patch: RulePatch, ledgerId: string): Promise<void> {
  const categoryExists = async (id: string) =>
    (await exec('SELECT 1 FROM categories WHERE id = ? AND ledger_id = ?', [id, ledgerId])).length > 0;
  if (typeof patch.categoryId === 'string' && !(await categoryExists(patch.categoryId))) {
    delete patch.categoryId;
  }
  if (typeof patch.counterpartyId === 'string'
      && (await exec('SELECT 1 FROM counterparties WHERE id = ?', [patch.counterpartyId])).length === 0) {
    delete patch.counterpartyId;
  }
  if (patch.splits) {
    for (const s of patch.splits) {
      if (s.categoryId != null && !(await categoryExists(s.categoryId))) { delete patch.splits; break; }
    }
  }
  if (patch.tagIdsAdd) {
    const kept: string[] = [];
    for (const id of patch.tagIdsAdd) {
      if ((await exec('SELECT 1 FROM tags WHERE id = ? AND ledger_id = ?', [id, ledgerId])).length > 0) kept.push(id);
    }
    patch.tagIdsAdd = kept;
  }
}

/** Whether a rule may re-kind an existing income/expense/refund entry to `kind`.
 *  A refund puts money back, so every account leg must be positive — the same rule
 *  the audit's kind-shape check holds it to. */
export async function canRekind(exec: Exec, entryId: string, kind: string): Promise<boolean> {
  if (!RULED_KINDS.includes(kind)) return false;
  if (kind !== 'refund') return true;
  const [{ n }] = await exec(
    'SELECT COUNT(*) AS n FROM postings WHERE entry_id = ? AND account_id IS NOT NULL AND amount <= 0',
    [entryId],
  );
  return Number(n) === 0;
}
