// DB-backed transaction interactions, run server-side against the shared DB
// (lib/db/server.ts). Reads return the store's `Tx` shape so the projected
// state can feed the store directly.

import type { Exec } from '@/lib/db/repo';
import type { Tx } from '@/lib/store';
import { convertToBase } from './rates';
import { resolveCounterpartyIdByName } from './counterparties';

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
}

export function rowToTx(r: Record<string, unknown>): Tx {
  // The store/derive `amount` is the ledger-base figure (DB `amount_base`);
  // DB `amount` is the native amount the user entered, kept for display.
  const amount = Number(r.amount_base);
  const nativeAmount = Number(r.amount);
  return {
    id: String(r.id),
    merchant: String(r.description ?? ''),
    category: r.category_id === null || r.category_id === undefined ? null : String(r.category_id),
    amount,
    currency: r.currency == null ? undefined : String(r.currency),
    nativeAmount,
    account: String(r.account_id),
    date: String(r.date),
    time: r.time == null ? undefined : String(r.time),
    note: r.notes == null ? undefined : String(r.notes),
    pending: String(r.status) === 'pending',
    kind: String(r.kind) as Tx['kind'],
    ledgerId: String(r.ledger_id),
    transferGroupId: r.transfer_group_id == null ? undefined : String(r.transfer_group_id),
    sourceTemplateId: r.source_template_id == null ? undefined : String(r.source_template_id),
    refundedTransactionId: r.refunded_transaction_id == null ? undefined : String(r.refunded_transaction_id),
    counterpartyId: r.counterparty_id == null ? undefined : String(r.counterparty_id),
    clearedAt: r.cleared_at == null ? null : String(r.cleared_at),
  };
}

/** List transactions for a ledger with optional search / filters. */
export async function listTransactions(exec: Exec, opts: ListOptions): Promise<Tx[]> {
  const where: string[] = ['ledger_id = ?'];
  const bind: (string | number | null)[] = [opts.ledgerId];

  if (opts.direction === 'in') where.push('amount > 0');
  if (opts.direction === 'out') where.push('amount < 0');
  if (opts.query) {
    const fts = toFts5Query(opts.query);
    if (fts) {
      // Inverted-index lookup via the transactions_fts shadow (description + notes).
      // Tokens are matched as prefixes, AND-joined — "blue bottle" ⇒ blue* AND bottle*.
      where.push('id IN (SELECT id FROM transactions_fts WHERE transactions_fts MATCH ?)');
      bind.push(fts);
    }
  }
  if (opts.accountId) {
    where.push('account_id = ?');
    bind.push(opts.accountId);
  }
  if (opts.categoryId) {
    where.push('category_id = ?');
    bind.push(opts.categoryId);
  }
  if (opts.status) {
    where.push('status = ?');
    bind.push(opts.status);
  }
  if (opts.from) {
    where.push('date >= ?');
    bind.push(opts.from);
  }
  if (opts.to) {
    where.push('date <= ?');
    bind.push(opts.to);
  }
  if (opts.minAmount != null) {
    where.push('ABS(amount_base) >= ?');
    bind.push(opts.minAmount);
  }
  if (opts.maxAmount != null) {
    where.push('ABS(amount_base) <= ?');
    bind.push(opts.maxAmount);
  }

  let sql = `SELECT * FROM transactions WHERE ${where.join(' AND ')} ORDER BY date DESC, time DESC`;
  if (opts.limit != null) {
    sql += ' LIMIT ?';
    bind.push(opts.limit);
    sql += ' OFFSET ?';
    bind.push(opts.offset ?? 0);
  }
  const rows = await exec(sql, bind);
  return rows.map(rowToTx);
}

export async function getTransaction(exec: Exec, id: string): Promise<Tx | null> {
  const rows = await exec('SELECT * FROM transactions WHERE id = ?', [id]);
  return rows[0] ? rowToTx(rows[0]) : null;
}

function newId(): string {
  return `t-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

/**
 * The shape every transaction-insert path normalizes to. One row per call.
 * Callers from different contexts (user add, transfer leg, scheduled post,
 * auto-generated pending, seed bulk import) all funnel through `insertTxRow`
 * so the column list, default resolution, and column drift live in one
 * place. Optional fields fall back to:
 *
 *   - `id`               → freshly generated `t-…`
 *   - `currency`         → the account's currency (one SELECT)
 *   - `amountBase`/`rate` → `convertToBase(amount, currency, ledger.base, date)`
 *   - `counterpartyId`   → `resolveCounterpartyIdByName(ledgerId, description)`
 *   - `status`           → `'confirmed'`
 *   - `confirmedAt`      → `now` when confirmed, NULL when pending
 *   - `timestamp`        → `new Date().toISOString()` for created_at/updated_at
 *
 * Bulk callers (seed) skip the resolutions they already did by passing the
 * concrete values; one-off callers (mutations, addTransaction) leave them
 * undefined and pay the per-row lookups.
 */
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
}

/**
 * The single insert path for the `transactions` table. See `NewTxRow` for
 * defaults and which call sites pre-resolve which fields. Returns the row's
 * id (caller-supplied or freshly generated).
 *
 * Confirmed rows fire the AFTER INSERT trigger that moves the account
 * balance; pending rows don't. The FTS5 shadow stays in sync via its own
 * triggers regardless.
 */
export async function insertTxRow(exec: Exec, row: NewTxRow): Promise<string> {
  const id = row.id ?? newId();
  const status = row.status ?? 'confirmed';
  const ts = row.timestamp ?? new Date().toISOString();

  // Currency: the account's, unless the caller already resolved it.
  let currency = row.currency;
  if (currency === undefined) {
    const [acct] = await exec('SELECT currency FROM accounts WHERE id = ?', [row.accountId]);
    currency = String(acct?.currency ?? 'USD');
  }

  // amount_base + rate: caller-supplied (seed already batched the
  // conversion) or one convertToBase round-trip on the row's date.
  let amountBase: number;
  let exchangeRate: number;
  if (row.amountBase !== undefined && row.exchangeRate !== undefined) {
    amountBase = row.amountBase;
    exchangeRate = row.exchangeRate;
  } else {
    const [l] = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [row.ledgerId]);
    const ledgerBase = String(l?.base_currency ?? currency);
    const conv = await convertToBase(exec, row.amount, currency, ledgerBase, row.date);
    amountBase = conv.amountBase;
    exchangeRate = conv.rate;
  }

  // Counterparty: caller's value (including explicit null), otherwise resolve.
  const counterpartyId = row.counterpartyId !== undefined
    ? row.counterpartyId
    : await resolveCounterpartyIdByName(exec, row.ledgerId, row.description);

  const confirmedAt = status === 'confirmed' ? ts : null;

  await exec(
    `INSERT INTO transactions
      (id,ledger_id,account_id,date,time,amount,amount_base,exchange_rate,
       description,category_id,counterparty_id,transfer_group_id,refunded_transaction_id,
       kind,status,confirmed_at,currency,notes,source_template_id,created_at,updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
    [
      id, row.ledgerId, row.accountId, row.date, row.time ?? null,
      row.amount, amountBase, exchangeRate,
      row.description, row.categoryId ?? null, counterpartyId,
      row.transferGroupId ?? null, row.refundedTransactionId ?? null,
      row.kind, status, confirmedAt,
      currency, row.notes ?? null, row.sourceTemplateId ?? null,
      ts, ts,
    ],
  );
  return id;
}

/** Insert a transaction; confirmed rows move the account balance via the insert trigger. */
export async function addTransaction(exec: Exec, input: AddInput): Promise<string> {
  // `amount` is native (in `currency`); the row's ledger-base figure is
  // derived inside insertTxRow from the row's currency + date. Kind defaults
  // to income/expense by amount sign; the caller can override (refund,
  // adjustment, transfer). An explicit `counterpartyId` is forwarded as-is;
  // insertTxRow skips the name-based auto-resolve when present.
  //
  // Cross-ledger guard: if the caller passes a `counterpartyId` from a
  // different ledger, drop the hint and let `insertTxRow` fall through to
  // the name-based auto-resolve. This keeps the FK in scope — counterparty
  // ids are not portable across ledgers.
  let counterpartyId = input.counterpartyId ?? undefined;
  if (counterpartyId) {
    const [cp] = await exec('SELECT ledger_id FROM counterparties WHERE id = ?', [counterpartyId]);
    if (!cp || String(cp.ledger_id) !== input.ledgerId) {
      counterpartyId = undefined;
    }
  }
  const kind = input.kind ?? (input.amount > 0 ? 'income' : 'expense');
  return await insertTxRow(exec, {
    ledgerId: input.ledgerId,
    accountId: input.accountId,
    date: input.date,
    time: input.time ?? null,
    amount: input.amount,
    currency: input.currency,
    description: input.merchant,
    categoryId: input.categoryId ?? null,
    kind,
    status: input.status ?? 'confirmed',
    refundedTransactionId: input.refundedTransactionId ?? null,
    notes: input.note || null,
    counterpartyId,
  });
}

/** Refunds linked back to an original expense (newest first). Used by the
 *  transaction detail page to show "refunded $X" against the original. */
export async function getRefundsFor(exec: Exec, originalId: string): Promise<Tx[]> {
  const rows = await exec(
    "SELECT * FROM transactions WHERE refunded_transaction_id = ? AND kind = 'refund' ORDER BY date DESC, time DESC",
    [originalId],
  );
  return rows.map(rowToTx);
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
 *     against the new currency at the (possibly edited) date.
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

export async function updateTransaction(
  exec: Exec,
  id: string,
  patch: TransactionPatch,
): Promise<{ oldAccountId: string | null }> {
  // Snapshot the row so the patch can be evaluated against the OLD values
  // (old account → returned to caller for recompute; old currency → used when
  // re-deriving amount_base without a currency patch; old status → drives the
  // confirmed_at flip; old date → rate lookup when date isn't in the patch).
  const [cur] = await exec(
    'SELECT account_id, currency, date, status FROM transactions WHERE id = ?',
    [id],
  );
  if (!cur) return { oldAccountId: null };
  const oldAccountId = String(cur.account_id);
  const oldCurrency = String(cur.currency ?? 'USD');
  const oldDate = String(cur.date);
  const oldStatus = String(cur.status);

  const sets: string[] = [];
  const bind: (string | number | null)[] = [];

  // -- Status: pending ↔ confirmed. confirmed_at moves with the flip.
  if (patch.status !== undefined && patch.status !== oldStatus) {
    sets.push('status = ?');
    bind.push(patch.status);
    if (patch.status === 'confirmed') {
      sets.push('confirmed_at = ?');
      bind.push(new Date().toISOString());
    } else {
      sets.push('confirmed_at = NULL');
    }
  }

  // -- Account: change FK. A cross-ledger account would orphan the row from
  //    the ledger's base currency and FX rules — reject it.
  let newAccountId = oldAccountId;
  if (patch.account !== undefined && patch.account !== oldAccountId) {
    const [acct] = await exec('SELECT ledger_id FROM accounts WHERE id = ?', [patch.account]);
    if (!acct) throw new Error('Account not found');
    // The transaction's ledger is fixed at insert time; accounts in a different
    // ledger are not eligible. We compare the row's ledger (not the account's
    // ledger — the row may have been inserted into a different ledger than its
    // current account under unusual conditions; the row's ledger is the
    // authoritative scope).
    const [rowLedger] = await exec('SELECT ledger_id FROM transactions WHERE id = ?', [id]);
    if (String(acct.ledger_id) !== String(rowLedger?.ledger_id)) {
      throw new Error('Account is in a different ledger');
    }
    sets.push('account_id = ?');
    bind.push(patch.account);
    newAccountId = String(patch.account);
  }

  // -- Currency: rewrite the row's native currency. The form's "amount" is
  //    the user-entered figure in the new currency, so we keep the magnitude
  //    but re-derive amount_base + exchange_rate. If `amount` is not in the
  //    patch, the existing magnitude is preserved.
  const currencyChanged = patch.currency !== undefined && patch.currency !== oldCurrency;
  if (currencyChanged || patch.amount !== undefined) {
    let amountToStore: number;
    if (patch.amount !== undefined) {
      amountToStore = patch.amount;
    } else {
      const [a] = await exec('SELECT amount FROM transactions WHERE id = ?', [id]);
      amountToStore = Number(a?.amount ?? 0);
    }
    const newCurrency = patch.currency ?? oldCurrency;
    const newDate = patch.date ?? oldDate;
    const [l] = await exec(
      'SELECT base_currency FROM ledgers WHERE id = (SELECT ledger_id FROM transactions WHERE id = ?)',
      [id],
    );
    const ledgerBase = String(l?.base_currency ?? newCurrency);
    const conv = await convertToBase(exec, amountToStore, newCurrency, ledgerBase, newDate);
    sets.push('amount = ?', 'amount_base = ?', 'exchange_rate = ?');
    bind.push(amountToStore, conv.amountBase, conv.rate);
    if (currencyChanged) {
      // `currencyChanged` already implies patch.currency !== undefined, but
      // the `let`/const narrowing through a derived boolean doesn't carry
      // that into `patch.currency` here. Re-check so the type stays `string`.
      if (patch.currency !== undefined) {
        sets.push('currency = ?');
        bind.push(patch.currency);
      }
    }
  }

  // -- Merchant: SET description + re-resolve the counterparty FK. --
  if (patch.merchant !== undefined) {
    sets.push('description = ?');
    bind.push(patch.merchant);
    // Re-resolve the catalog link: a rename to a name that matches a
    // counterparty wires the FK; a rename away from a known name nulls it.
    const [row] = await exec('SELECT ledger_id FROM transactions WHERE id = ?', [id]);
    const ledgerId = String(row?.ledger_id ?? '');
    const cpId = ledgerId ? await resolveCounterpartyIdByName(exec, ledgerId, patch.merchant) : null;
    sets.push('counterparty_id = ?');
    bind.push(cpId);
  }

  if (patch.category !== undefined) { sets.push('category_id = ?'); bind.push(patch.category); }
  if (patch.date !== undefined) { sets.push('date = ?'); bind.push(patch.date); }
  if (patch.time !== undefined) { sets.push('time = ?'); bind.push(patch.time ?? null); }
  if (patch.note !== undefined) { sets.push('notes = ?'); bind.push(patch.note ?? null); }
  // Reclassification (e.g. converting an income into a refund): both the kind and
  // the link to the offset expense move together. amount/sign is unchanged — an
  // income and a refund are both stored positive.
  if (patch.kind !== undefined) { sets.push('kind = ?'); bind.push(patch.kind); }
  if (patch.refundedTransactionId !== undefined) { sets.push('refunded_transaction_id = ?'); bind.push(patch.refundedTransactionId ?? null); }

  if (!sets.length) return { oldAccountId: null };
  sets.push("updated_at = datetime('now')");
  bind.push(id);
  await exec(`UPDATE transactions SET ${sets.join(', ')} WHERE id = ?`, bind);

  // Surface the OLD account id only when the row actually moved, so the
  // dispatcher's "recompute source account" step is a no-op for same-account
  // edits.
  return { oldAccountId: newAccountId !== oldAccountId ? oldAccountId : null };
}

/** Hard-delete a transaction (tags/splits cascade). Returns its account_id so the
 *  caller can recompute that account's balance afterward. */
export async function deleteTransactionRow(exec: Exec, id: string): Promise<string | null> {
  const rows = await exec('SELECT account_id FROM transactions WHERE id = ?', [id]);
  if (!rows.length) return null;
  await exec('DELETE FROM transactions WHERE id = ?', [id]);
  return String(rows[0].account_id);
}

/** Confirm a pending transaction so it counts in reports. */
export async function confirmTransaction(exec: Exec, id: string): Promise<void> {
  await exec("UPDATE transactions SET status = 'confirmed', confirmed_at = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'", [
    new Date().toISOString(),
    id,
  ]);
}

/**
 * Confirm a pending transaction and (optionally) link it to a counterparty
 * in the same write. Used by the Pending page after the matcher decides
 * where a row belongs. Counterparty resolution priority mirrors
 * `addTransaction`: explicit `counterpartyId` > `newCounterpartyName` (create
 * + link) > leave the existing link untouched. The row's `description` is
 * rewritten to the canonical counterparty name; the projection in
 * `state.ts` will further surface it as the row's `merchant` on read.
 */
export async function confirmPendingWithMerchant(
  exec: Exec,
  id: string,
  resolution: { counterpartyId?: string | null; newCounterpartyName?: string | null },
): Promise<void> {
  const [row] = await exec('SELECT description, ledger_id FROM transactions WHERE id = ?', [id]);
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
    "UPDATE transactions SET status = 'confirmed', confirmed_at = ?, counterparty_id = ?, description = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'",
    [new Date().toISOString(), counterpartyId, description, id],
  );
}
