// Read + admin operations on the ledgers table.
//
// The ledger base currency is mutable via `recomputeAmountBases`: changing
// the base forces a full rewrite of every locked `amount_base` (transactions,
// transaction_splits) under the new base + locked rate per transaction date.
// Account current balances are then re-derived from opening + Σ deltas.
//
// Full CRUD (create / rename / restyle / set-default / delete) lives in
// LEDGER_CRUD_PLAN — see §3 + §5 for the design.

import type { Exec } from '@/lib/db/repo';
import { convertToBase } from './rates';
import { recomputeAccount } from './accounts';

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
            (SELECT COUNT(*) FROM transactions t
              WHERE t.ledger_id = l.id) AS txns
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
      'SELECT rel_path FROM transaction_attachments WHERE ledger_id = ?',
      [id],
    );
    const relPaths = attachRows.map((r) => String(r.rel_path));

    // Ordered deletes from leaves up to the root. Rows in tables not
    // listed here (transaction_tags, transaction_splits, scheduled_splits)
    // follow via their own FK CASCADE off the rows we delete here.
    await exec('DELETE FROM transaction_attachments WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM transactions WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM scheduled_templates WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM rules WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM holdings WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM budgets WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM budget_groups WHERE ledger_id = ?', [id]);
    await exec('DELETE FROM transfer_groups WHERE ledger_id = ?', [id]);
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
 * transaction's date + native currency to look up rates. Updates:
 *   - ledgers.base_currency to newBase
 *   - transactions.amount_base + exchange_rate
 *   - transaction_splits.amount_base (per-split, same conversion logic)
 *   - accounts.current_balance via recomputeAccount (because cross-currency
 *     rows now produce different account-currency deltas after the rebuild)
 *
 * Idempotent: running with the current base is a no-op (each row reconverts
 * to the same figure). Wrapped in BEGIN/COMMIT so a mid-run failure leaves
 * the ledger in its pre-call state.
 */
export async function recomputeAmountBases(
  exec: Exec,
  ledgerId: string,
  newBase: string,
): Promise<{ transactions: number; splits: number; accounts: number }> {
  // SAVEPOINT (not BEGIN) so this composes with an outer transaction. SQLite
  // rejects nested BEGINs — and while no caller wraps us today, the API
  // route's mutation queue is the kind of place a future "batch these"
  // wrapper would slot in. RELEASE on success, ROLLBACK TO on failure.
  const sp = 'recompute_bases';
  await exec(`SAVEPOINT ${sp}`);
  try {
    await exec(
      "UPDATE ledgers SET base_currency = ?, updated_at = datetime('now') WHERE id = ?",
      [newBase, ledgerId],
    );

    const txns = await exec(
      'SELECT id, date, currency, amount FROM transactions WHERE ledger_id = ?',
      [ledgerId],
    );
    for (const t of txns) {
      const conv = await convertToBase(
        exec,
        Number(t.amount),
        String(t.currency),
        newBase,
        String(t.date),
      );
      await exec(
        "UPDATE transactions SET amount_base = ?, exchange_rate = ?, updated_at = datetime('now') WHERE id = ?",
        [conv.amountBase, conv.rate, String(t.id)],
      );
    }

    // Splits carry their own amount_base in the ledger base. Native amount and
    // currency follow the parent's, so the same convertToBase applies.
    const splits = await exec(
      `SELECT ts.id, ts.amount, t.currency, t.date
         FROM transaction_splits ts JOIN transactions t ON t.id = ts.transaction_id
        WHERE t.ledger_id = ?`,
      [ledgerId],
    );
    for (const s of splits) {
      const conv = await convertToBase(
        exec,
        Number(s.amount),
        String(s.currency),
        newBase,
        String(s.date),
      );
      await exec(
        'UPDATE transaction_splits SET amount_base = ? WHERE id = ?',
        [conv.amountBase, String(s.id)],
      );
    }

    // Account balances are stored in each account's own currency, but the
    // trigger's choice of delta (native vs amount_base) depends on whether
    // the txn currency matches the account currency. Foreign rows on
    // account-currency-matches-old-base accounts changed meaning, so rebuild.
    // The locked opening_balance_base must also move to the new base — same
    // creation-date rate, just expressed against newBase via the USD pivot.
    const accts = await exec(
      'SELECT id, currency, opening_balance, created_at FROM accounts WHERE ledger_id = ?',
      [ledgerId],
    );
    for (const a of accts) {
      const createdDate = String(a.created_at ?? '').slice(0, 10);
      const conv = await convertToBase(
        exec,
        Number(a.opening_balance ?? 0),
        String(a.currency),
        newBase,
        createdDate,
      );
      await exec(
        "UPDATE accounts SET opening_balance_base = ?, updated_at = datetime('now') WHERE id = ?",
        [conv.amountBase, String(a.id)],
      );
      await recomputeAccount(exec, String(a.id));
    }

    await exec(`RELEASE ${sp}`);
    return { transactions: txns.length, splits: splits.length, accounts: accts.length };
  } catch (err) {
    await exec(`ROLLBACK TO ${sp}`);
    await exec(`RELEASE ${sp}`);
    throw err;
  }
}
