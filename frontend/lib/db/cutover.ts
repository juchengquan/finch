// lib/db/cutover.ts — DOUBLE_ENTRY_PLAN §8.2 data-move builder.
//
// WHY MANUAL SEALED INSERTS (not postEntry)?
//   postEntry re-fires the rules engine, resolves counterparties, and may
//   re-derive exchange rates. The cutover MUST preserve locked figures verbatim
//   — amounts, rates, counterparty_id, applied_rule_ids, reviewed_at, etc. are
//   all carried over unchanged. Using postEntry would silently alter history.
//   Instead we INSERT entries with sealed=0, INSERT postings, then UPDATE
//   entries SET sealed=1 which fires the balance-check trigger (I1/I2) — same
//   two-phase write, without the rules/counterparty overhead.
//
// ID-FIDELITY TABLE (§8.3):
//   Legacy id        → New id
//   transactions.id (single)  → entries.id  AND  postings.id (account leg)
//   transactions.id (xfer leg)→ postings.id (account leg of the transfer entry)
//   transfer_groups.id        → entries.id  (the transfer entry)
//   transaction_splits.id     → postings.id (category legs of a split entry)
//   Opening balance           → entries.id = 'open-<accountId>'
//                               postings.id (acct leg) = 'open-<accountId>-a'
//                               postings.id (cat leg)  = 'open-<accountId>-c0'
//
// TORN-WRITE REPAIR (entryDone):
//   A previous run may have partially written an entry (sealed=0) before
//   crashing. entryDone detects this and cascades-deletes the partial entry so
//   the redo path rebuilds it cleanly. A sealed entry means the previous run
//   already succeeded; skip it (idempotence). Never DELETE a sealed entry —
//   that would destroy real data.

import type { Exec } from '@/lib/db/repo';
import { ensureSystemCategories, recomputeAccountFromPostings, auditLedger } from './entries';
import { convertToBase } from './queries/rates';
import { I18nError } from '@/lib/i18n-error';

const r2 = (n: number) => Math.round(n * 100) / 100;
const r6 = (n: number) => Math.round(n * 1e6) / 1e6;

// Re-export the hash function type for internal use — we import the real one
// from entries.ts at the end to avoid a circular-type dependency.
// Actually we just duplicate the hash logic here since dedupHash in entries.ts
// now accepts Array<{accountId: string|null; amount: number}> which exactly
// matches what we need.
import { dedupHash } from './entries';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Per-entry idempotence/repair guard.
 *  Returns true  → entry is already sealed, skip it.
 *  Returns false → entry is absent (normal) or was torn (partial write cleaned
 *                  up by cascade-delete so caller can insert fresh). */
async function entryDone(exec: Exec, id: string): Promise<boolean> {
  const rows = await exec('SELECT id, sealed FROM entries WHERE id = ?', [id]);
  if (!rows.length) return false;
  if (Number(rows[0].sealed) === 1) return true;
  // sealed = 0 means a torn previous run — cascade-delete and redo.
  await exec('DELETE FROM entries WHERE id = ?', [id]);
  return false;
}

interface RawLeg {
  id: string;
  accountId: string | null;
  categoryId: string | null;
  amount: number;
  currency: string;
  amountBase: number;
  exchangeRate: number;
  origAmount: number | null;
  origCurrency: string | null;
  memo: string | null;
  clearedAt: string | null;
}

interface EntryHeader {
  id: string;
  ledgerId: string;
  date: string;
  time: string | null;
  description: string | null;
  kind: string;
  status: string;
  confirmedAt: string | null;
  counterpartyId: string | null;
  refundedEntryId: string | null;
  sourceTemplateId: string | null;
  notes: string | null;
  appliedRuleIds: string | null;
  reviewedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

/** Insert an entry (sealed=0), its postings, then seal it (fires the
 *  balance-check trigger). NO savepoint — idempotence + the end audit are
 *  the safety net; a torn entry is repaired by entryDone on replay. */
async function insertSealedEntry(exec: Exec, hdr: EntryHeader, legs: RawLeg[]): Promise<void> {
  const hash = dedupHash(hdr.date, hdr.time, hdr.description ?? '', legs);
  await exec(
    `INSERT INTO entries
       (id,ledger_id,date,time,description,kind,status,confirmed_at,
        counterparty_id,refunded_entry_id,source_template_id,notes,
        applied_rule_ids,reviewed_at,dedup_hash,sealed,created_at,updated_at)
     VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,?)`,
    [
      hdr.id, hdr.ledgerId, hdr.date, hdr.time, hdr.description,
      hdr.kind, hdr.status, hdr.confirmedAt,
      hdr.counterpartyId, hdr.refundedEntryId, hdr.sourceTemplateId, hdr.notes,
      hdr.appliedRuleIds, hdr.reviewedAt, hash,
      hdr.createdAt, hdr.updatedAt,
    ],
  );
  for (let i = 0; i < legs.length; i++) {
    const l = legs[i];
    await exec(
      `INSERT INTO postings
         (id,entry_id,account_id,category_id,amount,currency,amount_base,
          exchange_rate,orig_amount,orig_currency,memo,cleared_at,sort_order)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [
        l.id, hdr.id, l.accountId, l.categoryId,
        l.amount, l.currency, l.amountBase, l.exchangeRate,
        l.origAmount, l.origCurrency, l.memo, l.clearedAt, i,
      ],
    );
  }
  await exec('UPDATE entries SET sealed = 1 WHERE id = ?', [hdr.id]);
}

/** Append an FX residue leg when Σ amountBase is not zero (§5.1 / I1).
 *  Threshold 0.005 — same as postEntry's appendResidue.
 *  The residue leg id is `${entryId}-fx` (canonical per §8.3). */
function appendResidueIfNeeded(legs: RawLeg[], fxCategoryId: string, base: string, entryId: string): void {
  const residue = r2(legs.reduce((s, l) => s + l.amountBase, 0));
  if (Math.abs(residue) >= 0.005) {
    legs.push({
      id: `${entryId}-fx`,
      accountId: null,
      categoryId: fxCategoryId,
      amount: r2(-residue),
      currency: base,
      amountBase: r2(-residue),
      exchangeRate: 1,
      origAmount: null,
      origCurrency: null,
      memo: null,
      clearedAt: null,
    });
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export interface CutoverResult {
  entries: number;
  postings: number;
}

/**
 * Move all legacy (transactions / transfer_groups / transaction_splits /
 * transaction_tags / transaction_attachments) data into the double-entry
 * (entries / postings / entry_tags / entry_attachments) tables.
 *
 * Contract (DOUBLE_ENTRY_PLAN §8.2), in this exact order:
 *   1. Prefetch: ledgers, system categories, accounts.
 *   2. Transfers (transfer_groups with exactly 2 legs).
 *   3. Singles + strays (every transaction not moved above).
 *   4. Opening entries (per account with non-zero opening_balance).
 *   5. Tags → entry_tags.
 *   6. Attachments → entry_attachments.
 *   7. Recompute all touched accounts + auditLedger (abort on any problem).
 *
 * Idempotent: sealed entries are skipped; torn (sealed=0) entries are
 * cascade-deleted and re-inserted.
 */
export async function moveLegacyData(exec: Exec): Promise<CutoverResult> {
  let entriesInserted = 0;
  let postingsInserted = 0;

  // -------------------------------------------------------------------------
  // 1. Prefetch
  // -------------------------------------------------------------------------
  const ledgerRows = await exec('SELECT id, base_currency FROM ledgers');
  const baseByLedger = new Map<string, string>();
  for (const r of ledgerRows) baseByLedger.set(String(r.id), String(r.base_currency));

  // System categories per ledger.
  const sysByLedger = new Map<string, { opening: string; adjustment: string; fx: string }>();
  for (const [ledgerId] of baseByLedger) {
    sysByLedger.set(ledgerId, await ensureSystemCategories(exec, ledgerId));
  }

  // Account maps: currency, ledger_id, opening_balance, opening_balance_base, created_at.
  const acctRows = await exec(
    'SELECT id, currency, ledger_id, opening_balance, opening_balance_base, created_at FROM accounts',
  );
  const acctCurrency = new Map<string, string>();
  const acctLedger = new Map<string, string>();
  const acctOpening = new Map<string, number>();
  const acctOpeningBase = new Map<string, number>();
  const acctCreatedAt = new Map<string, string>();
  for (const r of acctRows) {
    const id = String(r.id);
    acctCurrency.set(id, String(r.currency));
    acctLedger.set(id, String(r.ledger_id));
    acctOpening.set(id, Number(r.opening_balance));
    acctOpeningBase.set(id, Number(r.opening_balance_base));
    acctCreatedAt.set(id, String(r.created_at));
  }

  // Track all account ids that appear in postings so we can recompute them.
  const touchedAccountIds = new Set<string>();

  // Track which transaction ids have been moved as transfer legs (to skip in singles).
  const movedTxnIds = new Set<string>();

  // -------------------------------------------------------------------------
  // 2. Transfers: each transfer_group with exactly 2 legs.
  // -------------------------------------------------------------------------
  const tgRows = await exec(
    'SELECT id, ledger_id, notes FROM transfer_groups',
  );

  for (const tg of tgRows) {
    const entryId = String(tg.id);
    const tgLedgerId = String(tg.ledger_id);
    const base = baseByLedger.get(tgLedgerId) ?? 'SGD';
    const sys = sysByLedger.get(tgLedgerId)!;

    // Fetch the two transaction legs for this group.
    const legTxns = await exec(
      'SELECT id, account_id, date, time, amount, currency, amount_base, exchange_rate, status, confirmed_at, notes, source_template_id, reviewed_at, created_at, updated_at FROM transactions WHERE transfer_group_id = ? ORDER BY date, id',
      [entryId],
    );

    if (legTxns.length !== 2) {
      // Fewer or more than 2 legs — these are strays; they'll be handled in step 3.
      continue;
    }

    // Mark these transaction ids as moved.
    for (const leg of legTxns) movedTxnIds.add(String(leg.id));

    if (await entryDone(exec, entryId)) continue;

    // Header fields derived from the two legs.
    const dates = legTxns.map((l) => String(l.date));
    const entryDate = dates.reduce((a, b) => (a >= b ? a : b)); // MAX(date)
    const entryTime = legTxns.map((l) => l.time).find((t) => t != null) ?? null;
    // Both legs reviewed → use the earlier timestamp.
    const reviewedAts = legTxns.map((l) => (l.reviewed_at == null ? null : String(l.reviewed_at)));
    const entryReviewedAt =
      reviewedAts.every((r) => r != null)
        ? reviewedAts.sort()[0]!
        : null;
    const bothConfirmed = legTxns.every((l) => String(l.status) === 'confirmed');
    const entryStatus = bothConfirmed ? 'confirmed' : 'pending';
    const confirmedAt = legTxns.map((l) => (l.confirmed_at == null ? null : String(l.confirmed_at))).find((c) => c != null) ?? null;
    const entryNotes = tg.notes != null ? String(tg.notes) : (legTxns.map((l) => l.notes).find((n) => n != null) != null ? String(legTxns.map((l) => l.notes).find((n) => n != null)) : null);
    const sourceTemplateId = legTxns.map((l) => l.source_template_id).find((s) => s != null) != null ? String(legTxns.map((l) => l.source_template_id).find((s) => s != null)) : null;
    const createdAt = legTxns.map((l) => String(l.created_at)).sort()[0];
    const updatedAt = legTxns.map((l) => String(l.updated_at)).sort().reverse()[0];

    // Build account legs.
    const legs: RawLeg[] = [];
    for (const leg of legTxns) {
      const legId = String(leg.id);
      const legAccountId = String(leg.account_id);
      const legCurrency = String(leg.currency);
      const acctCcy = acctCurrency.get(legAccountId) ?? legCurrency;

      let amount = Number(leg.amount);
      let currency = legCurrency;
      const amountBase = Number(leg.amount_base);
      const exchangeRate = Number(leg.exchange_rate);
      let origAmount: number | null = null;
      let origCurrency: string | null = null;

      // F3 fix: if the row's currency != account's currency, re-denominate
      // into the account's currency. Treat as the "JPY hotel on the SGD card"
      // case (§5.2). The locked amount_base is kept; only the native side shifts.
      if (legCurrency !== acctCcy) {
        origAmount = amount;
        origCurrency = legCurrency;
        if (acctCcy === base) {
          // Account is in the ledger base: amount_base IS already the native
          // figure in that currency — use it directly to satisfy I9 (amount ==
          // amount_base when currency == base_currency).
          amount = amountBase;
        } else {
          const conv = await convertToBase(exec, amount, legCurrency, acctCcy, String(leg.date));
          amount = conv.amountBase; // re-denominated native in account currency
        }
        currency = acctCcy;
        // amount_base (ledger base) stays locked as the row's existing figure.
      }

      // Transfer memo: the leg's description = the old description field.
      // The transactions table carries `description` for transfers; use it as memo.
      const legDescRow = await exec('SELECT description FROM transactions WHERE id = ?', [legId]);
      const memo = legDescRow.length && legDescRow[0].description != null ? String(legDescRow[0].description) : null;

      legs.push({
        id: legId,
        accountId: legAccountId,
        categoryId: null,
        amount: r2(amount),
        currency,
        amountBase: r2(amountBase),
        exchangeRate,
        origAmount,
        origCurrency,
        memo,
        clearedAt: leg.cleared_at != null ? String(leg.cleared_at) : null,
      });
      touchedAccountIds.add(legAccountId);
    }

    // Residue leg.
    appendResidueIfNeeded(legs, sys.fx, base, entryId);

    const hdr: EntryHeader = {
      id: entryId,
      ledgerId: tgLedgerId,
      date: entryDate,
      time: entryTime != null ? String(entryTime) : null,
      description: 'Transfer',
      kind: 'transfer',
      status: entryStatus,
      confirmedAt,
      counterpartyId: null,
      refundedEntryId: null,
      sourceTemplateId,
      notes: entryNotes,
      appliedRuleIds: null,
      reviewedAt: entryReviewedAt,
      createdAt,
      updatedAt,
    };

    await insertSealedEntry(exec, hdr, legs);
    entriesInserted++;
    postingsInserted += legs.length;
  }

  // -------------------------------------------------------------------------
  // 3. Singles + strays: every transaction not moved above.
  // -------------------------------------------------------------------------
  const allTxns = await exec(
    `SELECT id, ledger_id, account_id, date, time, amount, currency, amount_base,
            exchange_rate, description, category_id, counterparty_id, transfer_group_id,
            refunded_transaction_id, kind, status, confirmed_at, source_template_id,
            notes, cleared_at, applied_rule_ids, reviewed_at, created_at, updated_at
       FROM transactions ORDER BY date, id`,
  );

  for (const txn of allTxns) {
    const txnId = String(txn.id);
    if (movedTxnIds.has(txnId)) continue; // already handled as a transfer leg

    if (await entryDone(exec, txnId)) continue;

    const txnAccountId = String(txn.account_id);
    const txnLedgerId = String(txn.ledger_id);
    const txnDate = String(txn.date);
    const base = baseByLedger.get(txnLedgerId) ?? 'SGD';
    const sys = sysByLedger.get(txnLedgerId)!;
    const acctCcy = acctCurrency.get(txnAccountId) ?? String(txn.currency);

    let entryKind = String(txn.kind) as string;
    // Orphan transfer legs (kind='transfer' but not moved above) → reclassify as adjustment.
    if (entryKind === 'transfer') entryKind = 'adjustment';

    // Build account leg.
    const txnCurrency = String(txn.currency);
    let amount = Number(txn.amount);
    let currency = txnCurrency;
    const amountBase = Number(txn.amount_base);
    const exchangeRate = Number(txn.exchange_rate);
    let origAmount: number | null = null;
    let origCurrency: string | null = null;

    // F3 fix: re-denominate native into the account's currency if mismatched.
    if (txnCurrency !== acctCcy) {
      origAmount = amount;
      origCurrency = txnCurrency;
      if (acctCcy === base) {
        // Account is in the ledger base: amount_base IS already the native
        // figure in that currency — use it directly to satisfy I9 (amount ==
        // amount_base when currency == base_currency).
        amount = amountBase;
      } else {
        const conv = await convertToBase(exec, amount, txnCurrency, acctCcy, txnDate);
        amount = conv.amountBase; // re-denominated native in account currency
      }
      currency = acctCcy;
    }

    const acctLeg: RawLeg = {
      id: txnId, // id-fidelity: account leg id = transaction id
      accountId: txnAccountId,
      categoryId: null,
      amount: r2(amount),
      currency,
      amountBase: r2(amountBase),
      exchangeRate,
      origAmount,
      origCurrency,
      memo: null,
      clearedAt: txn.cleared_at != null ? String(txn.cleared_at) : null,
    };
    touchedAccountIds.add(txnAccountId);

    const legs: RawLeg[] = [acctLeg];

    // Category legs.
    if (entryKind === 'adjustment') {
      // adjustment (incl. re-kinded orphan transfers) → equity adjustment leg.
      legs.push({
        id: `${txnId}-c0`,
        accountId: null,
        categoryId: sys.adjustment,
        amount: r2(-amountBase),
        currency: base,
        amountBase: r2(-amountBase),
        exchangeRate: 1,
        origAmount: null,
        origCurrency: null,
        memo: null,
        clearedAt: null,
      });
    } else {
      // income / expense / refund: check for splits first.
      const splits = await exec(
        'SELECT id, category_id, amount, amount_base, description FROM transaction_splits WHERE transaction_id = ? ORDER BY sort_order',
        [txnId],
      );
      if (splits.length > 0) {
        // One category leg per split (ids reused, signs NEGATED per postings convention).
        for (const sp of splits) {
          legs.push({
            id: String(sp.id),
            accountId: null,
            categoryId: sp.category_id != null ? String(sp.category_id) : null,
            amount: r2(-Number(sp.amount_base)), // sign negated; category legs base-denominated
            currency: base,
            amountBase: r2(-Number(sp.amount_base)),
            exchangeRate: 1,
            origAmount: null,
            origCurrency: null,
            memo: sp.description != null ? String(sp.description) : null,
            clearedAt: null,
          });
        }
      } else {
        // Single category leg.
        legs.push({
          id: `${txnId}-c0`,
          accountId: null,
          categoryId: txn.category_id != null ? String(txn.category_id) : null,
          amount: r2(-amountBase),
          currency: base,
          amountBase: r2(-amountBase),
          exchangeRate: 1,
          origAmount: null,
          origCurrency: null,
          memo: null,
          clearedAt: null,
        });
      }
      // Residue rule for cross-currency rounding.
      appendResidueIfNeeded(legs, sys.fx, base, txnId);
    }

    const hdr: EntryHeader = {
      id: txnId,
      ledgerId: txnLedgerId,
      date: txnDate,
      time: txn.time != null ? String(txn.time) : null,
      description: txn.description != null ? String(txn.description) : null,
      kind: entryKind,
      status: String(txn.status),
      confirmedAt: txn.confirmed_at != null ? String(txn.confirmed_at) : null,
      counterpartyId: txn.counterparty_id != null ? String(txn.counterparty_id) : null,
      // refunded_transaction_id values ARE entry ids by construction (§8.3).
      refundedEntryId: txn.refunded_transaction_id != null ? String(txn.refunded_transaction_id) : null,
      sourceTemplateId: txn.source_template_id != null ? String(txn.source_template_id) : null,
      notes: txn.notes != null ? String(txn.notes) : null,
      appliedRuleIds: txn.applied_rule_ids != null ? String(txn.applied_rule_ids) : null,
      reviewedAt: txn.reviewed_at != null ? String(txn.reviewed_at) : null,
      createdAt: String(txn.created_at),
      updatedAt: String(txn.updated_at),
    };

    await insertSealedEntry(exec, hdr, legs);
    entriesInserted++;
    postingsInserted += legs.length;
  }

  // -------------------------------------------------------------------------
  // 4. Opening entries: per account with non-zero opening_balance.
  // -------------------------------------------------------------------------
  for (const [acctId, openingBalance] of acctOpening) {
    if (r2(openingBalance) === 0) continue;

    const entryId = `open-${acctId}`;
    if (await entryDone(exec, entryId)) continue;

    const openingBalanceBase = acctOpeningBase.get(acctId) ?? openingBalance;
    const ledgerId = acctLedger.get(acctId)!;
    const base = baseByLedger.get(ledgerId) ?? 'SGD';
    const sys = sysByLedger.get(ledgerId)!;
    const acctCcy = acctCurrency.get(acctId) ?? base;
    const createdAt = acctCreatedAt.get(acctId) ?? new Date().toISOString();
    const entryDate = createdAt.slice(0, 10); // YYYY-MM-DD

    const exchangeRate = openingBalance !== 0 ? r6(openingBalanceBase / openingBalance) : 1;

    const legs: RawLeg[] = [
      {
        id: `${entryId}-a`,
        accountId: acctId,
        categoryId: null,
        amount: r2(openingBalance),
        currency: acctCcy,
        amountBase: r2(openingBalanceBase),
        exchangeRate,
        origAmount: null,
        origCurrency: null,
        memo: null,
        clearedAt: createdAt, // pre-cleared: opening IS the reconcile anchor
      },
      {
        id: `${entryId}-c0`,
        accountId: null,
        categoryId: sys.opening,
        amount: r2(-openingBalanceBase),
        currency: base,
        amountBase: r2(-openingBalanceBase),
        exchangeRate: 1,
        origAmount: null,
        origCurrency: null,
        memo: null,
        clearedAt: null,
      },
    ];

    // Residue rule (covers historical rounding in opening_balance_base).
    appendResidueIfNeeded(legs, sys.fx, base, entryId);

    const hdr: EntryHeader = {
      id: entryId,
      ledgerId,
      date: entryDate,
      time: null,
      description: 'Opening balance',
      kind: 'opening',
      status: 'confirmed',
      confirmedAt: createdAt,
      counterpartyId: null,
      refundedEntryId: null,
      sourceTemplateId: null,
      notes: null,
      appliedRuleIds: null,
      reviewedAt: null,
      createdAt,
      updatedAt: createdAt,
    };

    await insertSealedEntry(exec, hdr, legs);
    touchedAccountIds.add(acctId);
    entriesInserted++;
    postingsInserted += legs.length;
  }

  // -------------------------------------------------------------------------
  // 5. Tags → entry_tags.
  //    The entries JOIN is a FK-guard: rows whose entry didn't materialize are
  //    silently dropped (e.g. a transaction that had no valid entry path).
  // -------------------------------------------------------------------------
  await exec(`
    INSERT OR IGNORE INTO entry_tags (entry_id, tag_id)
    SELECT COALESCE(t.transfer_group_id, tt.transaction_id), tt.tag_id
      FROM transaction_tags tt
      JOIN transactions t ON t.id = tt.transaction_id
      JOIN entries e ON e.id = COALESCE(t.transfer_group_id, tt.transaction_id)
  `);

  // -------------------------------------------------------------------------
  // 6. Attachments → entry_attachments.
  // -------------------------------------------------------------------------
  await exec(`
    INSERT OR IGNORE INTO entry_attachments
      (id, ledger_id, entry_id, kind, rel_path, mime_type, byte_size, sha256,
       original_filename, created_at, updated_at)
    SELECT a.id, a.ledger_id,
           COALESCE(t.transfer_group_id, a.transaction_id),
           a.kind, a.rel_path, a.mime_type, a.byte_size, a.sha256,
           a.original_filename, a.created_at, a.updated_at
      FROM transaction_attachments a
      JOIN transactions t ON t.id = a.transaction_id
      JOIN entries e ON e.id = COALESCE(t.transfer_group_id, a.transaction_id)
  `);

  // -------------------------------------------------------------------------
  // 7. Recompute all touched accounts + audit.
  // -------------------------------------------------------------------------
  for (const acctId of touchedAccountIds) {
    await recomputeAccountFromPostings(exec, acctId);
  }

  const problems = await auditLedger(exec, undefined, { checkBalances: true });
  if (problems.length) {
    throw new I18nError(
      'error.migration.auditFailed',
      { count: problems.length },
      `Cutover audit failed: ${problems[0].code} ${problems[0].detail}`,
    );
  }

  return { entries: entriesInserted, postings: postingsInserted };
}

/**
 * Drop all legacy tables and triggers (registered by Task B5 in MIGRATIONS).
 * Ordered so FK-referencing children drop before parents.
 *
 * Module comment: this function is intentionally NOT called from moveLegacyData
 * — the migration registration task (B5) calls it after the data move so the
 * legacy surface disappears atomically at the end of the full migration.
 */
export async function dropLegacyTables(exec: Exec): Promise<void> {
  // Drop FTS sync triggers first (they reference transactions).
  await exec('DROP TRIGGER IF EXISTS tr_txn_fts_insert');
  await exec('DROP TRIGGER IF EXISTS tr_txn_fts_delete');
  await exec('DROP TRIGGER IF EXISTS tr_txn_fts_update');
  // Drop the balance trigger.
  await exec('DROP TRIGGER IF EXISTS tr_update_account_balance');
  // Drop the FTS virtual table and its shadow tables.
  await exec('DROP TABLE IF EXISTS transactions_fts');
  // Children before parents (FK order).
  await exec('DROP TABLE IF EXISTS transaction_attachments');
  await exec('DROP TABLE IF EXISTS transaction_tags');
  await exec('DROP TABLE IF EXISTS transaction_splits');
  await exec('DROP TABLE IF EXISTS transactions');
  await exec('DROP TABLE IF EXISTS transfer_groups');
}
