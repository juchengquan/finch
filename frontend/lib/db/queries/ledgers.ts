// Read + admin operations on the ledgers table.
//
// The ledger base currency is mutable via `recomputeAmountBases`: changing
// the base forces a full rewrite of every locked `amount_base` (entries/
// postings) under the new base + locked rate per entry date. Account current
// balances are then re-derived from postings via recomputeAccount.
//
// Full CRUD (create / rename / restyle / set-default / delete) lives in
// LEDGER_CRUD_PLAN — see §3 + §5 for the design.

import type { Exec } from '@/lib/db/repo';
import { convertToBase } from './rates';
import { rebuildEntry, auditLedger, ensureSystemCategories } from '@/lib/db/entries';
import { I18nError } from '@/lib/i18n-error';

export interface LedgerRow {
  id: string;
  name: string;
  base: string;
  isDefault: number;
  /** Accent dot in the switcher; null = derive a hue from the id. */
  color: string | null;
  /** One-line description shown in the switcher dropdown. */
  tagline: string | null;
  /** Live count of active accounts in this ledger (subselect). */
  accounts: number;
  /** Live count of transactions in this ledger (subselect). */
  txns: number;
}

/** List ledgers — projected so the UI can react when one's base flips.
 *  Includes live `accounts` + `txns` counts via subselects so the switcher
 *  reflects reality (LEDGER_CRUD_PLAN §3). Cheap at finch's scale (a handful
 *  of ledgers); each subselect uses the existing per-table ledger_id index. */
export async function listLedgers(exec: Exec): Promise<LedgerRow[]> {
  const rows = await exec(
    `SELECT l.id, l.name, l.base_currency AS base, l.is_default AS isDefault,
            l.color, l.tagline,
            (SELECT COUNT(*) FROM accounts a
              WHERE a.ledger_id = l.id AND a.is_active = 1) AS accounts,
            (SELECT COUNT(*) FROM entries e
              WHERE e.ledger_id = l.id AND e.kind != 'opening') AS txns
       FROM ledgers l
      ORDER BY l.is_default DESC, l.name`,
  );
  return rows.map((r) => ({
    id: String(r.id),
    name: String(r.name),
    base: String(r.base),
    isDefault: Number(r.isDefault),
    color: r.color == null ? null : String(r.color),
    tagline: r.tagline == null ? null : String(r.tagline),
    accounts: Number(r.accounts ?? 0),
    txns: Number(r.txns ?? 0),
  }));
}

export interface NewLedgerInput {
  id: string;
  name: string;
  base: string;
  color?: string | null;
  tagline?: string | null;
}

/** Insert a new ledger row. `is_default = 0` always; promote via
 *  `setDefaultLedger`. The caller validates inputs (LEDGER_CRUD_PLAN §4). */
export async function createLedger(exec: Exec, input: NewLedgerInput): Promise<void> {
  await exec(
    "INSERT INTO ledgers (id, name, base_currency, is_default, color, tagline, created_at, updated_at) " +
      "VALUES (?, ?, ?, 0, ?, ?, datetime('now'), datetime('now'))",
    [input.id, input.name, input.base, input.color ?? null, input.tagline ?? null],
  );
}

export interface LedgerPatch {
  name?: string;
  color?: string | null;
  tagline?: string | null;
}

/** Update a ledger's editable cosmetic fields. Base currency stays on the
 *  dedicated `recomputeAmountBases` path (it has reconversion semantics). */
export async function updateLedger(exec: Exec, id: string, patch: LedgerPatch): Promise<void> {
  const sets: string[] = [];
  const bind: (string | number | null)[] = [];
  if (patch.name !== undefined) { sets.push('name = ?'); bind.push(patch.name); }
  if (patch.color !== undefined) { sets.push('color = ?'); bind.push(patch.color); }
  if (patch.tagline !== undefined) { sets.push('tagline = ?'); bind.push(patch.tagline); }
  if (!sets.length) return;
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE ledgers SET ${sets.join(', ')} WHERE id = ?`, bind);
}

/** Flip `is_default = 1` on `id`, clearing it on every other ledger. Wrapped
 *  in a SAVEPOINT so a mid-flip failure leaves exactly the prior default
 *  in place. */
export async function setDefaultLedger(exec: Exec, id: string): Promise<void> {
  const sp = 'set_default_ledger';
  await exec(`SAVEPOINT ${sp}`);
  try {
    await exec("UPDATE ledgers SET is_default = 0, updated_at = datetime('now')");
    await exec(
      "UPDATE ledgers SET is_default = 1, updated_at = datetime('now') WHERE id = ?",
      [id],
    );
    await exec(`RELEASE ${sp}`);
  } catch (err) {
    await exec(`ROLLBACK TO ${sp}`);
    await exec(`RELEASE ${sp}`);
    throw err;
  }
}

/** Delete a ledger and every child row in a SAVEPOINT, then return the
 *  attachment rel_paths the caller should unlink from disk *after* the
 *  swap commits (LEDGER_CRUD_PLAN §5). Explicit ordered deletes — not raw
 *  FK cascade — because `transactions.account_id` is RESTRICT and SQLite's
 *  cross-table cascade ordering isn't part of the contract. Also handles
 *  default reassignment (first ledger by name) and refuses to delete the
 *  only remaining ledger.
 *
 *  Returns `{ relPaths, newDefaultId }`. The caller sweeps `relPaths` from
 *  disk and (if `newDefaultId != null`) knows the default moved. */
export async function deleteLedger(exec: Exec, id: string): Promise<{ relPaths: string[]; newDefaultId: string | null }> {
  // Guard #1: target exists.
  const target = await exec('SELECT id, is_default FROM ledgers WHERE id = ?', [id]);
  if (!target.length) throw new Error('Ledger not found');
  const wasDefault = Number(target[0].is_default) === 1;

  // Guard #2: not the last ledger.
  const remainingCount = Number(
    (await exec('SELECT COUNT(*) AS n FROM ledgers WHERE id != ?', [id]))[0]?.n ?? 0,
  );
  if (remainingCount === 0) throw new Error('Cannot delete the last ledger');

  const sp = 'delete_ledger';
  await exec(`SAVEPOINT ${sp}`);
  try {
    // Collect attachment rel_paths BEFORE the rows go away — caller unlinks
    // them after the savepoint releases.
    const attachRows = await exec(
      'SELECT rel_path FROM entry_attachments WHERE ledger_id = ?',
      [id],
    );
    const relPaths = attachRows.map((r) => String(r.rel_path));

    // Ordered deletes from leaves up to the root. postings, entry_tags, and
    // entry_attachments follow via FK CASCADE when entries are deleted.
    await exec('DELETE FROM entry_attachments WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM entries WHERE ledger_id = ?', [id]); // postings/entry_tags cascade
    await exec('DELETE FROM scheduled_templates WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM rules WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM holdings WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM budgets WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM budget_groups WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM accounts WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM account_groups WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM categories WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM tags WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM counterparties WHERE ledger_id = ?', [id]);

    // Default reassignment: promote the first remaining ledger by name.
    let newDefaultId: string | null = null;
    if (wasDefault) {
      const next = await exec(
        'SELECT id FROM ledgers WHERE id != ? ORDER BY name LIMIT 1',
        [id],
      );
      if (next.length) {
        newDefaultId = String(next[0].id);
        await exec(
          "UPDATE ledgers SET is_default = 1, updated_at = datetime('now') WHERE id = ?",
          [newDefaultId],
        );
      }
    }

    await exec('DELETE FROM ledgers WHERE id = ?', [id]);
    await exec(`RELEASE ${sp}`);
    return { relPaths, newDefaultId };
  } catch (err) {
    await exec(`ROLLBACK TO ${sp}`);
    await exec(`RELEASE ${sp}`);
    throw err;
  }
}

/**
 * Rewrite every locked `amount_base` in `ledgerId` against `newBase` using each
 * entry's date + native currency to look up rates (DOUBLE_ENTRY_PLAN §5.3).
 * Per entry, inside a single SAVEPOINT:
 *   1. UPDATE ledgers.base_currency to newBase.
 *   2. For every entry in the ledger: read its postings; build a LegInput[]:
 *      - account legs: no amountBase (forces re-lock at the entry's own date
 *        under the new base); forward clearedAt/memo/orig/id.
 *      - category legs (excluding fx-system legs — dropped; rebuildEntry
 *        re-derives them): reconvert amount_base via convertToBase from the
 *        OLD base value to the NEW base at the entry's date; forward id/memo.
 *   3. rebuildEntry re-residues + reseals + recomputes touched accounts.
 *   4. auditLedger after the loop; throw I18nError on any problem.
 *
 * Idempotent: running with the current base reconverts to the same figures.
 * Wrapped in SAVEPOINT so a mid-run failure leaves the ledger unchanged.
 */
export async function recomputeAmountBases(
  exec: Exec,
  ledgerId: string,
  newBase: string,
): Promise<{ entries: number; accounts: number }> {
  const sp = 'recompute_bases';
  await exec(`SAVEPOINT ${sp}`);
  try {
    // Ensure system categories exist under the new base (fx-gain/loss etc.).
    await ensureSystemCategories(exec, ledgerId);

    // 1. Get old base before updating.
    const [ledgerRow] = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [ledgerId]);
    const oldBase = ledgerRow ? String(ledgerRow.base_currency) : newBase;

    await exec(
      "UPDATE ledgers SET base_currency = ?, updated_at = datetime('now') WHERE id = ?",
      [newBase, ledgerId],
    );

    // 2. Fetch all entries for this ledger.
    const entryRows = await exec(
      'SELECT id, date FROM entries WHERE ledger_id = ? ORDER BY date, id',
      [ledgerId],
    );

    const touchedAccountIds = new Set<string>();

    for (const entry of entryRows) {
      const entryId = String(entry.id);
      const entryDate = String(entry.date);

      // Read all postings for this entry.
      const postingRows = await exec(
        'SELECT id, account_id, category_id, amount, currency, amount_base, exchange_rate, orig_amount, orig_currency, cleared_at, memo FROM postings WHERE entry_id = ? ORDER BY sort_order',
        [entryId],
      );

      // Identify the fx-system category for this ledger (to drop residue legs).
      const fxRows = await exec(
        "SELECT id FROM categories WHERE ledger_id = ? AND system = 'fx'",
        [ledgerId],
      );
      const fxCatId = fxRows[0] ? String(fxRows[0].id) : null;

      // Build LegInput[] — see design §5.3.
      const legs: import('@/lib/db/entries').LegInput[] = [];
      for (const p of postingRows) {
        if (p.account_id != null) {
          // Account leg: omit amountBase so rebuildEntry re-locks at the new base.
          legs.push({
            id: String(p.id),
            accountId: String(p.account_id),
            amount: Number(p.amount),
            origAmount: p.orig_amount == null ? null : Number(p.orig_amount),
            origCurrency: p.orig_currency == null ? null : String(p.orig_currency),
            clearedAt: p.cleared_at == null ? null : String(p.cleared_at),
            memo: p.memo == null ? null : String(p.memo),
          });
          touchedAccountIds.add(String(p.account_id));
        } else {
          // Category leg: drop fx-system residue legs (rebuildEntry re-derives them).
          if (fxCatId != null && String(p.category_id) === fxCatId) continue;
          // Reconvert the OLD base-denominated amount to the NEW base at the entry date.
          const oldBaseValue = Number(p.amount_base);
          const conv = await convertToBase(exec, oldBaseValue, oldBase, newBase, entryDate);
          legs.push({
            id: String(p.id),
            categoryId: p.category_id == null ? null : String(p.category_id),
            amountBase: Math.round(conv.amountBase * 100) / 100,
            memo: p.memo == null ? null : String(p.memo),
          });
        }
      }

      await rebuildEntry(exec, entryId, { legs });
    }

    // 4. Audit after the loop.
    const problems = await auditLedger(exec, ledgerId, { checkBalances: true });
    if (problems.length) {
      throw new I18nError(
        'error.ledger.recomputeFailed',
        { count: problems.length },
        `recomputeAmountBases audit failed: ${problems[0].code} ${problems[0].detail}`,
      );
    }

    await exec(`RELEASE ${sp}`);
    return { entries: entryRows.length, accounts: touchedAccountIds.size };
  } catch (err) {
    await exec(`ROLLBACK TO ${sp}`);
    await exec(`RELEASE ${sp}`);
    throw err;
  }
}
