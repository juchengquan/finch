// DB-backed transaction interactions, run server-side against the shared DB
// (lib/db/server.ts). Reads return the store's `Tx` shape so the projected
// state can feed the store directly.

import type { Exec } from '@/lib/db/repo';
import type { Tx } from '@/lib/store';
import { convertToBase } from './rates';
import { resolveCounterpartyIdByName } from './counterparties';
import {
  postEntry, postSimple, rebuildEntry, deleteEntry, resolveEntryRef,
  recomputeAccountFromPostings,
  type EntryKind,
} from '@/lib/db/entries';
import { I18nError } from '@/lib/i18n-error';

/** Translate a user-typed search string into an FTS5 MATCH expression.
 *  Each run of unicode letters/numbers becomes a case-folded prefix term
 *  joined with AND. Splitting on punctuation (not just whitespace) matches
 *  the FTS5 `unicode61` tokenizer, which indexes `"O'Reilly"` as `o` and
 *  `reilly` — so a query of `"O'Reilly"` becomes `o* AND reilly*` and
 *  actually matches the stored row. Returns the empty string when nothing
 *  usable remains — callers should skip the filter in that case. */
function toFts5Query(raw: string): string {
  const tokens = [...raw.toLowerCase().matchAll(/[\p{L}\p{N}]+/gu)].map((m) => m[0]);
  if (tokens.length === 0) return '';
  return tokens.map((t) => `${t}*`).join(' AND ');
}

export type Direction = 'all' | 'in' | 'out';

export interface ListOptions {
  ledgerId: string;
  direction?: Direction;
  query?: string;
  accountId?: string;
  categoryId?: string;
  status?: 'pending' | 'confirmed';
  from?: string; // inclusive YYYY-MM-DD
  to?: string; // inclusive YYYY-MM-DD
  /** Filter by absolute amount, magnitude in the ledger base currency. */
  minAmount?: number;
  maxAmount?: number;
  limit?: number;
  offset?: number;
}

export interface AddInput {
  ledgerId: string;
  accountId: string;
  amount: number; // signed, native (in `currency`)
  amountBase?: number; // signed, ledger base; defaults to `amount` (same-currency)
  currency?: string; // native currency; defaults to the account's currency
  merchant: string;
  categoryId?: string | null;
  date: string;
  time?: string;
  note?: string;
  status?: 'pending' | 'confirmed';
  /** Explicit classification; defaults to income/expense by amount sign.
   *  'adjustment' is the manual balance-reconciliation kind; 'refund' is a
   *  positive row that nets against its category (see refundedTransactionId). */
  kind?: 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund';
  /** For kind='refund': the original expense this refund offsets. */
  refundedTransactionId?: string | null;
  /** Optional explicit counterparty link. When provided, the wrapper
   *  forwards it to `insertTxRow`, which uses it as the FK and skips the
   *  name-based auto-resolve. The projection in `state.ts` still overwrites
   *  `merchant` with the canonical counterparty name on read. */
  counterpartyId?: string | null;
  /** Bypass the rules engine for this insert. */
  skipRules?: boolean;
}

/** Map a joined posting+entry row to the partial Tx shape.
 *  Enrichment (category / splits / transferGroupId / refund / tags) is added
 *  by `enrichLegTxs` — callers MUST pass through that helper before returning
 *  Tx objects to the outside world. */
function legRowToTx(r: Record<string, unknown>): Tx {
  // p.amount_base is the ledger-base signed figure (store's `amount`).
  // p.amount (orig_amount ?? p.amount) is the native figure for display.
  const amount = Number(r.p_base);
  const nativeAmount = Number(r.orig_amount ?? r.p_amount);
  const currency = r.orig_currency != null ? String(r.orig_currency)
    : r.p_ccy != null ? String(r.p_ccy) : undefined;
  return {
    id: String(r.pid),
    merchant: String(r.p_memo ?? r.description ?? ''),
    category: null, // filled by enrichLegTxs
    amount,
    currency,
    nativeAmount,
    account: String(r.p_account),
    date: String(r.date),
    time: r.time == null ? undefined : String(r.time),
    note: r.notes == null ? undefined : String(r.notes),
    pending: String(r.status) === 'pending',
    kind: String(r.kind) as Tx['kind'],
    ledgerId: String(r.ledger_id),
    // transferGroupId filled by enrichLegTxs (multi-account-leg entries)
    sourceTemplateId: r.source_template_id == null ? undefined : String(r.source_template_id),
    // refundedTransactionId filled by enrichLegTxs
    counterpartyId: r.counterparty_id == null ? undefined : String(r.counterparty_id),
    clearedAt: r.p_cleared == null ? null : String(r.p_cleared),
    appliedRuleIds: parseRuleIds(r.applied_rule_ids),
    reviewedAt: r.reviewed_at == null ? null : String(r.reviewed_at),
  };
}

/** @deprecated alias for callers that still import rowToTx — forwards to legRowToTx.
 *  Remove once B4 sweep is complete. */
export const rowToTx = legRowToTx;

/** Parse the applied_rule_ids JSON array column; undefined when null/corrupt. */
function parseRuleIds(raw: unknown): string[] | undefined {
  if (raw == null) return undefined;
  try {
    const v = JSON.parse(String(raw));
    return Array.isArray(v) ? v.map(String) : undefined;
  } catch {
    return undefined;
  }
}

/** Base SELECT joining account postings to their entry header.
 *  Excludes opening entries and category legs (account_id IS NOT NULL). */
const BASE_SELECT = `
  SELECT p.id AS pid, p.account_id AS p_account, p.amount AS p_amount, p.amount_base AS p_base,
         p.currency AS p_ccy, p.orig_amount, p.orig_currency, p.cleared_at AS p_cleared, p.memo AS p_memo,
         e.id AS eid, e.ledger_id, e.date, e.time, e.description, e.kind, e.status, e.counterparty_id,
         e.refunded_entry_id, e.source_template_id, e.notes, e.applied_rule_ids, e.reviewed_at,
         e.created_at AS e_created_at
    FROM postings p JOIN entries e ON e.id = p.entry_id
   WHERE p.account_id IS NOT NULL AND e.kind != 'opening'
`;

/** Shared enrichment: category, splits, transferGroupId, refundedTransactionId,
 *  tags — all resolved in 4 batched queries over the entry-id set. */
export async function enrichLegTxs(exec: Exec, rows: Tx[], entryIds: string[]): Promise<Tx[]> {
  if (entryIds.length === 0) return rows;

  const ph = entryIds.map(() => '?').join(',');

  // 1. Category legs per entry (plain only — exclude equity). Select p.id for
  //    split-id fidelity (DOUBLE_ENTRY_PLAN §8.3: posting id = stable anchor).
  const catRows = await exec(
    `SELECT p.id, p.entry_id, p.category_id, p.amount_base, p.sort_order
       FROM postings p
      WHERE p.entry_id IN (${ph}) AND p.account_id IS NULL
        AND (p.category_id IS NULL OR (
          SELECT c.kind FROM categories c WHERE c.id = p.category_id
        ) != 'equity')
      ORDER BY p.entry_id, p.sort_order`,
    entryIds,
  );

  // 2. Account-leg count per entry (detects transfers: ≥2 account legs).
  const acctCountRows = await exec(
    `SELECT p.entry_id, COUNT(*) AS n
       FROM postings p
      WHERE p.entry_id IN (${ph}) AND p.account_id IS NOT NULL
      GROUP BY p.entry_id`,
    entryIds,
  );

  // 3. Tags per entry.
  const tagRows = await exec(
    `SELECT et.entry_id, et.tag_id FROM entry_tags et WHERE et.entry_id IN (${ph})`,
    entryIds,
  );

  // Build category map: entryId → plain category legs (sorted by sort_order).
  const catsByEntry = new Map<string, Array<{ id: string; categoryId: string | null; amountBase: number; sortOrder: number }>>();
  for (const cr of catRows) {
    const eid = String(cr.entry_id);
    const arr = catsByEntry.get(eid) ?? [];
    arr.push({
      id: String(cr.id),
      categoryId: cr.category_id == null ? null : String(cr.category_id),
      amountBase: Number(cr.amount_base),
      sortOrder: Number(cr.sort_order),
    });
    catsByEntry.set(eid, arr);
  }

  // Build account-leg-count map.
  const acctCountMap = new Map<string, number>();
  for (const ac of acctCountRows) acctCountMap.set(String(ac.entry_id), Number(ac.n));

  // Build tag map: entryId → tag ids.
  const tagsByEntry = new Map<string, string[]>();
  for (const tr of tagRows) {
    const eid = String(tr.entry_id);
    const arr = tagsByEntry.get(eid) ?? [];
    arr.push(String(tr.tag_id));
    tagsByEntry.set(eid, arr);
  }

  // Collect refunded_entry_ids that need resolution (raw entry ids).
  const refEntryIds = rows
    .filter((r) => r.refundedTransactionId != null)
    .map((r) => r.refundedTransactionId as string);

  const refPostingMap = new Map<string, string>();
  if (refEntryIds.length > 0) {
    const refPh = refEntryIds.map(() => '?').join(',');
    const refRows = await exec(
      `SELECT p.entry_id, p.id AS pid
         FROM postings p
        WHERE p.entry_id IN (${refPh}) AND p.account_id IS NOT NULL
        ORDER BY p.sort_order
        LIMIT ${refEntryIds.length}`,
      refEntryIds,
    );
    // Use first account leg per entry.
    for (const rr of refRows) {
      const eid = String(rr.entry_id);
      if (!refPostingMap.has(eid)) refPostingMap.set(eid, String(rr.pid));
    }
  }

  // Enrich each row in place.
  for (let i = 0; i < rows.length; i++) {
    const tx = rows[i];
    const eid = entryIds[i];

    // category / splits
    const legs = catsByEntry.get(eid) ?? [];
    if (legs.length === 0) {
      tx.category = null;
    } else if (legs.length === 1) {
      tx.category = legs[0].categoryId;
    } else {
      // ≥2 plain legs → category = largest |amount_base| leg
      const dominant = legs.reduce((best, l) =>
        Math.abs(l.amountBase) > Math.abs(best.amountBase) ? l : best, legs[0]);
      tx.category = dominant.categoryId;
      // splits in sort_order; negate amounts back to legacy parent-signed convention
      tx.splits = legs
        .slice()
        .sort((a, b) => a.sortOrder - b.sortOrder)
        .map((l) => ({
          // Use the stable posting id for split fidelity (DOUBLE_ENTRY_PLAN §8.3).
          id: l.id,
          categoryId: l.categoryId,
          amount: -l.amountBase,
          amountBase: -l.amountBase,
          description: null,
        }));
    }

    // transferGroupId: entry id when ≥2 account legs
    const acctCount = acctCountMap.get(eid) ?? 1;
    if (acctCount >= 2) tx.transferGroupId = eid;

    // refundedTransactionId: resolve raw entry id → first account-posting id
    if (tx.refundedTransactionId != null) {
      const resolved = refPostingMap.get(tx.refundedTransactionId);
      if (resolved) tx.refundedTransactionId = resolved;
    }

    // tags
    const tags = tagsByEntry.get(eid);
    if (tags && tags.length > 0) tx.tags = tags;
  }

  return rows;
}

/** List transactions for a ledger with optional search / filters. */
export async function listTransactions(exec: Exec, opts: ListOptions): Promise<Tx[]> {
  const where: string[] = ['e.ledger_id = ?'];
  const bind: (string | number | null)[] = [opts.ledgerId];

  if (opts.direction === 'in') where.push('p.amount > 0');
  if (opts.direction === 'out') where.push('p.amount < 0');
  if (opts.query) {
    const fts = toFts5Query(opts.query);
    if (fts) {
      where.push('e.id IN (SELECT id FROM entries_fts WHERE entries_fts MATCH ?)');
      bind.push(fts);
    }
  }
  if (opts.accountId) {
    where.push('p.account_id = ?');
    bind.push(opts.accountId);
  }
  if (opts.categoryId) {
    where.push(`EXISTS (SELECT 1 FROM postings cp
      JOIN categories cc ON cc.id = cp.category_id
      WHERE cp.entry_id = e.id AND cp.account_id IS NULL AND cp.category_id = ?)`);
    bind.push(opts.categoryId);
  }
  if (opts.status) {
    where.push('e.status = ?');
    bind.push(opts.status);
  }
  if (opts.from) {
    where.push('e.date >= ?');
    bind.push(opts.from);
  }
  if (opts.to) {
    where.push('e.date <= ?');
    bind.push(opts.to);
  }
  if (opts.minAmount != null) {
    where.push('ABS(p.amount_base) >= ?');
    bind.push(opts.minAmount);
  }
  if (opts.maxAmount != null) {
    where.push('ABS(p.amount_base) <= ?');
    bind.push(opts.maxAmount);
  }

  const extraWhere = where.length > 0 ? ` AND ${where.join(' AND ')}` : '';
  let sql = `${BASE_SELECT}${extraWhere} ORDER BY e.date DESC, e.time DESC, e.created_at DESC, p.sort_order`;
  if (opts.limit != null) {
    sql += ' LIMIT ?';
    bind.push(opts.limit);
    sql += ' OFFSET ?';
    bind.push(opts.offset ?? 0);
  }
  const rawRows = await exec(sql, bind);
  const partials = rawRows.map(legRowToTx);
  const entryIds = rawRows.map((r) => String(r.eid));
  return enrichLegTxs(exec, partials, entryIds);
}

export async function getTransaction(exec: Exec, id: string): Promise<Tx | null> {
  // Accept posting id or fall back to entry id.
  let rawRows = await exec(`${BASE_SELECT} AND p.id = ?`, [id]);
  if (!rawRows.length) {
    rawRows = await exec(`${BASE_SELECT} AND e.id = ? LIMIT 1`, [id]);
  }
  if (!rawRows.length) return null;
  const partial = legRowToTx(rawRows[0]);
  const entryId = String(rawRows[0].eid);
  const enriched = await enrichLegTxs(exec, [partial], [entryId]);
  return enriched[0] ?? null;
}

const r2 = (n: number) => Math.round(n * 100) / 100;

/** Insert a transaction via the entries chokepoint. Returns the ENTRY id.
 *  The client's optimistic flow replaces state from the server projection;
 *  the returned id feeds txTouches + rollover invalidation in mutations.ts.
 *
 *  Cross-ledger counterparty guard preserved: if the caller passes a
 *  counterpartyId from a different ledger, it is dropped and the
 *  name-based auto-resolve inside postEntry runs instead. */
export async function addTransaction(exec: Exec, input: AddInput): Promise<string> {
  // Cross-ledger counterparty guard (preserved from legacy path).
  let counterpartyId = input.counterpartyId ?? undefined;
  if (counterpartyId) {
    const [cp] = await exec('SELECT ledger_id FROM counterparties WHERE id = ?', [counterpartyId]);
    if (!cp || String(cp.ledger_id) !== input.ledgerId) {
      counterpartyId = undefined;
    }
  }

  const kind: EntryKind = (input.kind ?? (input.amount > 0 ? 'income' : 'expense')) as EntryKind;

  // §5.2: if input.currency is set and differs from the account's currency,
  // convert into the account's currency (fixes F3) and carry orig_* fields.
  const [acct] = await exec('SELECT currency FROM accounts WHERE id = ?', [input.accountId]);
  const acctCcy = String(acct?.currency ?? 'USD');
  const inputCcy = input.currency ?? acctCcy;

  if (inputCcy !== acctCcy) {
    // Foreign-currency entry: convert native → account currency then → ledger base.
    const [l] = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [input.ledgerId]);
    const ledgerBase = String(l?.base_currency ?? acctCcy);
    const convToAcct = await convertToBase(exec, input.amount, inputCcy, acctCcy, input.date);
    const convToBase2 = await convertToBase(exec, convToAcct.amountBase, acctCcy, ledgerBase, input.date);
    const { entryId } = await postEntry(exec, {
      ledgerId: input.ledgerId,
      date: input.date,
      time: input.time ?? null,
      description: input.merchant,
      kind,
      status: input.status ?? 'confirmed',
      notes: input.note || null,
      counterpartyId,
      refundedEntryId: input.refundedTransactionId ?? null,
      skipRules: input.skipRules,
      legs: [{
        accountId: input.accountId,
        amount: convToAcct.amountBase,  // account-native
        amountBase: convToBase2.amountBase,
        exchangeRate: convToBase2.rate,
        origAmount: input.amount,
        origCurrency: inputCcy,
      }],
      autoBalanceCategoryId: input.categoryId ?? null,
    });
    return entryId;
  }

  // Standard same-currency path via postSimple.
  const { entryId } = await postSimple(exec, {
    ledgerId: input.ledgerId,
    accountId: input.accountId,
    amount: input.amount,
    date: input.date,
    time: input.time ?? null,
    description: input.merchant,
    categoryId: input.categoryId ?? null,
    kind,
    status: input.status ?? 'confirmed',
    notes: input.note || null,
    counterpartyId,
    refundedEntryId: input.refundedTransactionId ?? null,
    skipRules: input.skipRules,
  });
  return entryId;
}

/** @deprecated B3b: this wrapper is DEAD CODE — all callers now go through
 *  addTransaction → postSimple/postEntry. Retained because state.ts still
 *  imports it (B4 will remove it). Callers from different contexts (user add,
 *  transfer leg, scheduled post, auto-generated pending, seed bulk import) all
 *  funnel through `insertTxRow`; optional fields fall back to resolved values
 *  (id, currency, amountBase/rate, counterpartyId, status, timestamp). */
export interface NewTxRow {
  ledgerId: string;
  accountId: string;
  date: string;
  time?: string | null;
  /** Signed native amount in `currency` (the account's currency). */
  amount: number;
  description: string;
  kind: 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund';
  /** Optional: omit to default to the account's own currency. */
  currency?: string;
  categoryId?: string | null;
  status?: 'pending' | 'confirmed';
  transferGroupId?: string | null;
  refundedTransactionId?: string | null;
  sourceTemplateId?: string | null;
  notes?: string | null;
  /** Pre-resolved (amount_base, rate) when the caller already has them
   *  (seed already converted the whole batch; recompute paths supply
   *  their own). Default: convert on the fly via `convertToBase`. */
  amountBase?: number;
  exchangeRate?: number;
  /** Pre-resolved counterparty id. Pass `null` to skip the lookup with a
   *  known-empty result; omit (undefined) to run the resolver. */
  counterpartyId?: string | null;
  /** Override the generated id (seed uses fixed ids). */
  id?: string;
  /** Override created/updated/confirmed timestamps (seed uses SEED_TS). */
  timestamp?: string;
  /** Bypass the rules engine for this insert. Used by seed (rules don't exist
   *  during seeding) and as an escape hatch for rule-generated rows that must
   *  not re-trigger rules (the infinite-loop guard). Default false. */
  skipRules?: boolean;
}

/** @deprecated insertTxRow is DEAD CODE as of B3b. All insert paths now go
 *  through addTransaction → postSimple/postEntry. Retained because state.ts
 *  still imports this type at B4 (will be removed then). */
export async function insertTxRow(exec: Exec, row: NewTxRow): Promise<string> {
  // Thin shim: delegate to addTransaction which uses postSimple/postEntry.
  return addTransaction(exec, {
    ledgerId: row.ledgerId,
    accountId: row.accountId,
    amount: row.amount,
    currency: row.currency,
    merchant: row.description,
    categoryId: row.categoryId ?? null,
    date: row.date,
    time: row.time ?? undefined,
    note: row.notes ?? undefined,
    status: row.status ?? 'confirmed',
    kind: row.kind as AddInput['kind'],
    refundedTransactionId: row.refundedTransactionId ?? null,
    counterpartyId: row.counterpartyId,
    skipRules: row.skipRules,
  });
}

/** Refunds linked back to an original expense (newest first). Used by the
 *  transaction detail page to show "refunded $X" against the original. */
export async function getRefundsFor(exec: Exec, originalId: string): Promise<Tx[]> {
  // Resolve the caller's id (may be a posting id or entry id) to an entry id.
  const ref = await resolveEntryRef(exec, originalId);
  const entryId = ref?.entryId ?? originalId;

  const rawRows = await exec(
    `${BASE_SELECT} AND e.refunded_entry_id = ? AND e.kind = 'refund'
     ORDER BY e.date DESC, e.time DESC`,
    [entryId],
  );
  const partials = rawRows.map(legRowToTx);
  const eids = rawRows.map((r) => String(r.eid));
  return enrichLegTxs(exec, partials, eids);
}

/**
 * Server-side patch shape. Mirrors the in-app `Tx` columns that are editable
 * via the edit-transaction sheet, plus three server-only fields the client
 * shape doesn't carry:
 *
 *   - `account`   — change the account FK. The OLD account is returned via
 *     `oldAccountId` so the dispatcher can recompute it (the row no longer
 *     contributes to its balance). Cross-ledger moves are rejected.
 *   - `currency`  — change the row's native currency. The form's `amount`
 *     stays as the user entered it; amount_base + exchange_rate are re-derived
 *     against the new currency at the (possibly edited) date. A `date`-only
 *     edit re-derives them too — the locked rate must always be the rate on
 *     the row's own date.
 *   - `status`    — flip pending ↔ confirmed. `confirmed_at` follows the flip
 *     (now on confirm, NULL on demote). The recompute step picks up the
 *     change in the account balance, since the balance sum is `confirmed`-only.
 */
export interface TransactionPatch {
  merchant?: Tx['merchant'];
  category?: Tx['category'];
  amount?: Tx['amount'];
  date?: Tx['date'];
  time?: Tx['time'];
  note?: Tx['note'];
  kind?: Tx['kind'];
  refundedTransactionId?: Tx['refundedTransactionId'];
  account?: string;
  currency?: string;
  status?: 'pending' | 'confirmed';
}

/** Full adapter rewrite of updateTransaction over the entries chokepoint.
 *  Preserves the legacy patch contract verbatim. Returns { oldAccountId }
 *  for the dispatcher's source-account recompute step. */
export async function updateTransaction(
  exec: Exec,
  id: string,
  patch: TransactionPatch,
): Promise<{ oldAccountId: string | null }> {
  const ref = await resolveEntryRef(exec, id);
  if (!ref) return { oldAccountId: null };
  const { entryId } = ref;

  // Load entry header + postings.
  const [cur] = await exec('SELECT * FROM entries WHERE id = ?', [entryId]);
  if (!cur) return { oldAccountId: null };
  const oldLegs = await exec('SELECT * FROM postings WHERE entry_id = ? ORDER BY sort_order', [entryId]);
  const acctLegs = oldLegs.filter((l) => l.account_id != null);

  // Guard: transfer entries may only get header-only patches.
  const touchesMoney = patch.amount !== undefined || patch.category !== undefined
    || patch.account !== undefined || patch.currency !== undefined || patch.kind !== undefined;
  if (acctLegs.length > 1 && touchesMoney) {
    throw new I18nError('error.entry.transferLegEdit', {}, 'Edit transfers from the Transfers screen');
  }

  const oldAccountId = acctLegs.length > 0 ? String(acctLegs[0].account_id) : null;

  // Build EntryPatch header fields.
  const entryPatch: import('@/lib/db/entries').EntryPatch = {};
  if (patch.date !== undefined) entryPatch.date = patch.date;
  if (patch.time !== undefined) entryPatch.time = patch.time ?? null;
  if (patch.note !== undefined) entryPatch.notes = patch.note ?? null;
  if (patch.kind !== undefined) entryPatch.kind = patch.kind as EntryKind;
  if (patch.refundedTransactionId !== undefined) entryPatch.refundedEntryId = patch.refundedTransactionId ?? null;
  if (patch.status !== undefined) entryPatch.status = patch.status;

  // Merchant → description + counterparty re-resolve.
  if (patch.merchant !== undefined) {
    entryPatch.description = patch.merchant;
    const ledgerId = String(cur.ledger_id ?? '');
    entryPatch.counterpartyId = ledgerId
      ? await resolveCounterpartyIdByName(exec, ledgerId, patch.merchant)
      : null;
  }

  // Determine if we need to rebuild legs.
  const rebuildLegs = patch.amount !== undefined || patch.currency !== undefined
    || patch.account !== undefined || patch.category !== undefined;

  if (!rebuildLegs) {
    // Header-only patch (date re-lock handled by rebuildEntry automatically).
    await rebuildEntry(exec, entryId, entryPatch);
    return { oldAccountId: null };
  }

  // Single-account-leg path: reconstruct legs fully resolved.
  const oldAcctLeg = acctLegs[0];
  if (!oldAcctLeg) return { oldAccountId: null };

  const [ledgerRow] = await exec(
    'SELECT base_currency FROM ledgers WHERE id = (SELECT ledger_id FROM entries WHERE id = ?)',
    [entryId],
  );
  const ledgerBase = String(ledgerRow?.base_currency ?? 'USD');

  const newAccountId = patch.account ?? String(oldAcctLeg.account_id);
  const [newAcctRow] = await exec('SELECT currency FROM accounts WHERE id = ?', [newAccountId]);
  const newAcctCcy = String(newAcctRow?.currency ?? String(oldAcctLeg.currency));

  const nativeTypedAmount = patch.amount !== undefined ? patch.amount : Number(oldAcctLeg.amount);
  const patchCcy = patch.currency ?? (patch.account !== undefined ? newAcctCcy : String(oldAcctLeg.currency));

  // Re-lock when amount/currency/date/account changed.
  const willRelock = patch.amount !== undefined || patch.currency !== undefined
    || patch.date !== undefined || patch.account !== undefined;

  let resolvedAmountBase: number;
  let resolvedRate: number;
  // §5.2: when the effective patch currency differs from the account's currency,
  // the user typed a foreign amount — mirror addTransaction's §5.2 two-step
  // conversion (foreign → account ccy → ledger base) and carry orig_* fields.
  let origAmount: number | null;
  let origCurrency: string | null;
  let nativeAmount: number; // amount stored on the account leg (in account currency)

  if (willRelock && patchCcy !== newAcctCcy) {
    // §5.2: foreign-currency input — two-step conversion to preserve orig fields.
    const effectiveDate = patch.date ?? String(cur.date);
    const convToAcct = await convertToBase(exec, nativeTypedAmount, patchCcy, newAcctCcy, effectiveDate);
    const convToBase2 = await convertToBase(exec, convToAcct.amountBase, newAcctCcy, ledgerBase, effectiveDate);
    nativeAmount = convToAcct.amountBase;  // account-native
    resolvedAmountBase = convToBase2.amountBase;
    resolvedRate = convToBase2.rate;
    origAmount = nativeTypedAmount;
    origCurrency = patchCcy;
  } else if (willRelock) {
    const effectiveDate = patch.date ?? String(cur.date);
    const conv = await convertToBase(exec, nativeTypedAmount, patchCcy, ledgerBase, effectiveDate);
    nativeAmount = nativeTypedAmount;
    resolvedAmountBase = conv.amountBase;
    resolvedRate = conv.rate;
    // Preserve existing orig fields (no currency flip).
    origAmount = oldAcctLeg.orig_amount == null ? null : Number(oldAcctLeg.orig_amount);
    origCurrency = oldAcctLeg.orig_currency == null ? null : String(oldAcctLeg.orig_currency);
  } else {
    // Pure category change: preserve the locked base/rate and orig fields.
    nativeAmount = nativeTypedAmount;
    resolvedAmountBase = Number(oldAcctLeg.amount_base);
    resolvedRate = Number(oldAcctLeg.exchange_rate);
    origAmount = oldAcctLeg.orig_amount == null ? null : Number(oldAcctLeg.orig_amount);
    origCurrency = oldAcctLeg.orig_currency == null ? null : String(oldAcctLeg.orig_currency);
  }

  // Splits: if ≥2 plain category legs and patch.category is set, no-op on
  // legs (legacy parity — sets the ignored parent default).
  const plainCatLegs = oldLegs.filter((l) => l.account_id == null);
  if (plainCatLegs.length >= 2 && patch.category !== undefined) {
    // Legacy parity: category patch on a split entry is a no-op on legs.
    await rebuildEntry(exec, entryId, entryPatch);
    return { oldAccountId: newAccountId !== (oldAccountId ?? '') ? (oldAccountId ?? null) : null };
  }

  // Single category leg.
  const existingCatLeg = plainCatLegs[0];
  const newCategoryId = patch.category !== undefined
    ? patch.category
    : (existingCatLeg ? (existingCatLeg.category_id == null ? null : String(existingCatLeg.category_id)) : null);

  const newLegs: import('@/lib/db/entries').LegInput[] = [
    {
      id: String(oldAcctLeg.id),
      accountId: newAccountId,
      amount: nativeAmount,
      amountBase: resolvedAmountBase,
      exchangeRate: resolvedRate,
      origAmount,
      origCurrency,
      clearedAt: oldAcctLeg.cleared_at == null ? null : String(oldAcctLeg.cleared_at),
      memo: oldAcctLeg.memo == null ? null : String(oldAcctLeg.memo),
    },
    {
      id: existingCatLeg ? String(existingCatLeg.id) : undefined,
      categoryId: newCategoryId,
      amountBase: r2(-resolvedAmountBase),
      memo: existingCatLeg?.memo == null ? null : String(existingCatLeg.memo),
    },
  ];

  entryPatch.legs = newLegs;
  await rebuildEntry(exec, entryId, entryPatch);

  const movedAccount = newAccountId !== (oldAccountId ?? '') ? (oldAccountId ?? null) : null;
  return { oldAccountId: movedAccount };
}

/** Hard-delete an entry (postings cascade). Returns the first touched account
 *  id so the caller can recompute that account's balance. */
export async function deleteTransactionRow(exec: Exec, id: string): Promise<string | null> {
  const ref = await resolveEntryRef(exec, id);
  if (!ref) return null;
  const { touchedAccountIds } = await deleteEntry(exec, ref.entryId);
  return touchedAccountIds[0] ?? null;
}

/** Confirm a pending entry so it counts in reports and moves balances. */
export async function confirmTransaction(exec: Exec, id: string): Promise<void> {
  const ref = await resolveEntryRef(exec, id);
  if (!ref) return;
  await exec(
    "UPDATE entries SET status = 'confirmed', confirmed_at = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'",
    [new Date().toISOString(), ref.entryId],
  );
  const acctLegs = await exec(
    'SELECT DISTINCT account_id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL',
    [ref.entryId],
  );
  for (const r of acctLegs) await recomputeAccountFromPostings(exec, String(r.account_id));
}

/**
 * Confirm a pending entry and (optionally) link it to a counterparty.
 * Counterparty resolution priority: explicit counterpartyId >
 * newCounterpartyName (create + link) > leave existing link untouched.
 */
export async function confirmPendingWithMerchant(
  exec: Exec,
  id: string,
  resolution: { counterpartyId?: string | null; newCounterpartyName?: string | null },
): Promise<void> {
  const ref = await resolveEntryRef(exec, id);
  if (!ref) return;
  const [row] = await exec('SELECT description, ledger_id FROM entries WHERE id = ?', [ref.entryId]);
  if (!row) return;
  const ledgerId = String(row.ledger_id ?? '');

  let counterpartyId: string | null = null;
  let description = String(row.description ?? '');
  if (resolution.counterpartyId) {
    const [cp] = await exec('SELECT name FROM counterparties WHERE id = ? AND ledger_id = ?', [
      resolution.counterpartyId,
      ledgerId,
    ]);
    if (cp) {
      counterpartyId = String(cp.id ?? resolution.counterpartyId);
      description = String(cp.name);
    }
  } else if (resolution.newCounterpartyName && resolution.newCounterpartyName.trim()) {
    const name = resolution.newCounterpartyName.trim();
    const newCpId = `cp-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
    await exec(
      "INSERT INTO counterparties (id,ledger_id,name,is_verified,created_at,updated_at) VALUES (?,?,?,0,datetime('now'),datetime('now'))",
      [newCpId, ledgerId, name],
    );
    counterpartyId = newCpId;
    description = name;
  }

  await exec(
    "UPDATE entries SET status = 'confirmed', confirmed_at = ?, counterparty_id = ?, description = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'",
    [new Date().toISOString(), counterpartyId, description, ref.entryId],
  );

  // Recompute balances.
  const acctLegs = await exec(
    'SELECT DISTINCT account_id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL',
    [ref.entryId],
  );
  for (const r of acctLegs) await recomputeAccountFromPostings(exec, String(r.account_id));
}
