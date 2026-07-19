// PR A of plans/DOUBLE_ENTRY_PLAN.md §3: the single write chokepoint for the
// entries/postings double-entry core. Nothing outside this module (and the
// PR B migration) writes those tables. Every function assumes the caller
// holds the API route's BEGIN/COMMIT (lib/db/server.ts:392); multi-statement
// writes compose via SAVEPOINT, the recomputeAmountBases idiom.

import { createHash } from 'node:crypto';
import type { Exec } from './repo';
import type { Tx } from '@/lib/store';
import { convertToBase } from '../queries/rates';
import { resolveCounterpartyIdByName } from '../queries/counterparties';
import { listActiveRules } from '../queries/rules';
import { applyRules } from '@/lib/rules/engine';

const newId = (prefix: string) =>
  `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;

const r2 = (n: number) => Math.round(n * 100) / 100;

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
  // Filled key-by-key by the loop below — every SYSTEM_CATEGORIES.system is a
  // key of SystemCategoryIds, so the assertion is satisfied by construction.
  const out = {} as SystemCategoryIds;
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
  return out;
}

// --- Leg inputs -------------------------------------------------------------

export interface AccountLegInput {
  accountId: string;
  /** Signed, in the account's own currency (I3). */
  amount: number;
  /** Pre-resolved conversion (seed/migration paths); derived via
   *  convertToBase at the entry date when absent. */
  amountBase?: number;
  exchangeRate?: number;
  origAmount?: number | null;
  origCurrency?: string | null;
  clearedAt?: string | null;
  memo?: string | null;
  id?: string;
}

export interface CategoryLegInput {
  categoryId: string | null;
  /** Signed, in the ledger base (category legs are base-denominated; I3/I9). */
  amountBase: number;
  memo?: string | null;
  id?: string;
}

export type LegInput = AccountLegInput | CategoryLegInput;
export const isAccountLeg = (l: LegInput): l is AccountLegInput => 'accountId' in l;

export interface NewEntry {
  id?: string;
  ledgerId: string;
  date: string;
  time?: string | null;
  description: string;
  kind: EntryKind;
  status?: EntryStatus;
  legs: LegInput[];
  /** When set (null = uncategorized), append one category leg that exactly
   *  negates the account legs — the common single-category case. */
  autoBalanceCategoryId?: string | null;
  notes?: string | null;
  /** undefined → resolve from description; null → skip the lookup. */
  counterpartyId?: string | null;
  refundedEntryId?: string | null;
  sourceTemplateId?: string | null;
  timestamp?: string;
  skipRules?: boolean;
}

interface ResolvedLeg {
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

function categoryLeg(id: string | undefined, categoryId: string | null, amountBase: number, base: string, memo: string | null): ResolvedLeg {
  return {
    id: id ?? newId('p'), accountId: null, categoryId,
    amount: amountBase, currency: base, amountBase, exchangeRate: 1,
    origAmount: null, origCurrency: null, memo, clearedAt: null,
  };
}

async function ledgerBase(exec: Exec, ledgerId: string): Promise<string> {
  const [l] = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [ledgerId]);
  if (!l) throw new Error('Ledger not found');
  return String(l.base_currency);
}

/** Resolve raw leg inputs: account currency + ledger guards (I3/I5), locked
 *  amount_base at the entry date unless the caller pre-resolved it. */
async function resolveLegs(exec: Exec, ledgerId: string, date: string, base: string, inputs: LegInput[]): Promise<ResolvedLeg[]> {
  const legs: ResolvedLeg[] = [];
  for (const leg of inputs) {
    if (isAccountLeg(leg)) {
      const [acct] = await exec('SELECT currency, ledger_id FROM accounts WHERE id = ?', [leg.accountId]);
      if (!acct) throw new Error('Account not found');
      if (String(acct.ledger_id) !== ledgerId) throw new Error('Account is in a different ledger');
      const currency = String(acct.currency);
      let amountBase = leg.amountBase;
      let exchangeRate = leg.exchangeRate;
      if (amountBase === undefined || exchangeRate === undefined) {
        const conv = await convertToBase(exec, leg.amount, currency, base, date);
        amountBase = conv.amountBase;
        exchangeRate = conv.rate;
      }
      legs.push({
        id: leg.id ?? newId('p'), accountId: leg.accountId, categoryId: null,
        amount: r2(leg.amount), currency, amountBase: r2(amountBase), exchangeRate,
        origAmount: leg.origAmount ?? null, origCurrency: leg.origCurrency ?? null,
        memo: leg.memo ?? null, clearedAt: leg.clearedAt ?? null,
      });
    } else {
      if (leg.categoryId != null) {
        const [cat] = await exec('SELECT ledger_id FROM categories WHERE id = ?', [leg.categoryId]);
        if (!cat) throw new Error('Category not found');
        if (String(cat.ledger_id) !== ledgerId) throw new Error('Category is in a different ledger');
      }
      legs.push(categoryLeg(leg.id, leg.categoryId, r2(leg.amountBase), base, leg.memo ?? null));
    }
  }
  return legs;
}

/** Whatever Σ amount_base leaves becomes an explicit fx equity leg, so the
 *  entry balances to the cent (I1 — no tolerance). */
async function appendResidue(exec: Exec, ledgerId: string, base: string, legs: ResolvedLeg[]): Promise<ResolvedLeg[]> {
  const residue = r2(legs.reduce((s, l) => s + l.amountBase, 0));
  if (Math.abs(residue) >= 0.005) {
    const sys = await ensureSystemCategories(exec, ledgerId);
    legs.push(categoryLeg(undefined, sys.fx, r2(-residue), base, null));
  }
  return legs;
}

async function categoryMeta(exec: Exec, legs: ResolvedLeg[]): Promise<Map<string, { kind: string; system: string | null }>> {
  const ids = [...new Set(legs.filter((l) => l.categoryId != null).map((l) => String(l.categoryId)))];
  const out = new Map<string, { kind: string; system: string | null }>();
  if (!ids.length) return out;
  const rows = await exec(
    `SELECT id, kind, system FROM categories WHERE id IN (${ids.map(() => '?').join(',')})`,
    ids,
  );
  for (const r of rows) out.set(String(r.id), { kind: String(r.kind), system: r.system == null ? null : String(r.system) });
  return out;
}

/** I7: the kind label must match the postings shape. */
function validateShape(kind: EntryKind, legs: ResolvedLeg[], meta: Map<string, { kind: string; system: string | null }>): void {
  const acct = legs.filter((l) => l.accountId != null);
  const cats = legs.filter((l) => l.accountId == null);
  if (legs.length < 2 || acct.length < 1) throw new Error('An entry needs at least two postings including an account leg');
  const sysOf = (l: ResolvedLeg) => (l.categoryId ? meta.get(l.categoryId)?.system ?? null : null);
  const equity = cats.filter((l) => l.categoryId != null && meta.get(l.categoryId)?.kind === 'equity');
  const plain = cats.filter((l) => !equity.includes(l));

  switch (kind) {
    case 'transfer':
      if (acct.length !== 2) throw new Error('A transfer has exactly two account legs');
      if (plain.length > 0) throw new Error('A transfer has no category leg');
      if (equity.some((l) => sysOf(l) !== 'fx')) throw new Error('Only the FX residue may balance a transfer');
      break;
    case 'opening':
    case 'adjustment': {
      const want = kind === 'opening' ? 'opening' : 'adjustment';
      const ok = acct.length === 1 && plain.length === 0
        && equity.some((l) => sysOf(l) === want)
        && equity.every((l) => sysOf(l) === want || sysOf(l) === 'fx');
      if (!ok) throw new Error(`An ${kind} entry is one account leg against the ${want} equity category`);
      break;
    }
    default: // income / expense / refund
      if (acct.length !== 1) throw new Error(`A ${kind} entry has exactly one account leg`);
      if (plain.length < 1) throw new Error(`A ${kind} entry needs a category leg`);
      if (equity.some((l) => sysOf(l) !== 'fx')) throw new Error('Equity categories cannot be booked directly');
      if (kind === 'refund' && acct[0].amount <= 0) throw new Error('A refund must be positive');
  }
}

/** Double-submit backstop. NULL when time is NULL — parity with the old
 *  idx_txn_dedup, whose NULL time never collided (scheduled auto-posts).
 *  Exported for cutover.ts, which assembles legs from raw DB rows (not the
 *  full ResolvedLeg shape); it only reads accountId + amount. */
export function dedupHash(date: string, time: string | null | undefined, description: string, legs: Array<{ accountId: string | null; amount: number }>): string | null {
  if (time == null) return null;
  const acct = legs
    .filter((l) => l.accountId != null)
    .map((l) => `${l.accountId}:${l.amount.toFixed(2)}`)
    .sort()
    .join(',');
  return createHash('sha256').update(`${date}|${time}|${description}|${acct}`).digest('hex');
}

async function insertPostings(exec: Exec, entryId: string, legs: ResolvedLeg[]): Promise<void> {
  for (let i = 0; i < legs.length; i++) {
    const l = legs[i];
    await exec(
      `INSERT INTO postings (id,entry_id,account_id,category_id,amount,currency,amount_base,exchange_rate,orig_amount,orig_currency,memo,cleared_at,sort_order)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [l.id, entryId, l.accountId, l.categoryId, l.amount, l.currency, l.amountBase, l.exchangeRate,
       l.origAmount, l.origCurrency, l.memo, l.clearedAt, i],
    );
  }
}

/** The single insert path for entries + postings (supersedes insertTxRow in
 *  PR B). Resolve → auto-balance → rules/counterparty → residue → validate →
 *  two-phase insert+seal inside a SAVEPOINT. */
export async function postEntry(exec: Exec, e: NewEntry): Promise<{ entryId: string }> {
  const entryId = e.id ?? newId('e');
  const ts = e.timestamp ?? new Date().toISOString();
  const status: EntryStatus = e.status ?? 'confirmed';
  const base = await ledgerBase(exec, e.ledgerId);

  const legs = await resolveLegs(exec, e.ledgerId, e.date, base, e.legs);

  if (e.autoBalanceCategoryId !== undefined) {
    const acctSum = r2(legs.filter((l) => l.accountId != null).reduce((s, l) => s + l.amountBase, 0));
    legs.push(categoryLeg(undefined, e.autoBalanceCategoryId, r2(-acctSum), base, null));
  }

  let description = e.description;
  let notes = e.notes ?? null;
  let kind = e.kind;
  let counterpartyId: string | null = e.counterpartyId !== undefined
    ? e.counterpartyId
    : await resolveCounterpartyIdByName(exec, e.ledgerId, description);
  let appliedRuleIds: string[] | null = null;
  let tagIdsAdd: string[] | null = null;
  let reviewedAt: string | null = null;

  // Rules engine — income/expense/refund only, mirroring insertTxRow's hook.
  const RULED: EntryKind[] = ['income', 'expense', 'refund'];
  if (!e.skipRules && RULED.includes(kind)) {
    const rules = await listActiveRules(exec, e.ledgerId);
    if (rules.length > 0) {
      const acctLeg = legs.find((l) => l.accountId != null);
      if (!acctLeg) throw new Error(`A ${kind} entry has exactly one account leg`);
      const firstCat = legs.find((l) => l.accountId == null);
      const synthetic: Tx = {
        id: entryId, merchant: description, category: firstCat?.categoryId ?? null,
        amount: acctLeg.amountBase, nativeAmount: acctLeg.amount, currency: acctLeg.currency,
        account: acctLeg.accountId as string, date: e.date, time: e.time ?? undefined,
        note: notes ?? undefined, pending: status === 'pending', kind: kind as Tx['kind'],
        ledgerId: e.ledgerId, sourceTemplateId: e.sourceTemplateId ?? undefined,
        refundedTransactionId: e.refundedEntryId ?? undefined,
        counterpartyId: counterpartyId ?? undefined, tags: [],
      };
      const patch = applyRules(synthetic, rules);
      if (patch.appliedRuleIds.length > 0) {
        if (patch.merchant !== undefined) description = patch.merchant;
        if (patch.note !== undefined) notes = patch.note;
        if (patch.kind !== undefined && RULED.includes(patch.kind as EntryKind)) kind = patch.kind as EntryKind;
        if (patch.counterpartyId !== undefined) counterpartyId = patch.counterpartyId;
        if (patch.categoryId !== undefined) {
          const cl = legs.find((l) => l.accountId == null);
          if (cl) cl.categoryId = patch.categoryId;
        }
        if (patch.splits && patch.splits.length >= 2) {
          // Replace category legs with fraction-derived ones over the account
          // leg; last split absorbs the rounding remainder (insertTxRow's
          // logic, with category legs as the NEGATION of the leg's share).
          const ratio = acctLeg.amount !== 0 ? acctLeg.amountBase / acctLeg.amount : 1;
          for (let i = legs.length - 1; i >= 0; i--) if (legs[i].accountId == null) legs.splice(i, 1);
          let remaining = acctLeg.amount;
          // The last split absorbs the rounding remainder in BOTH native and
          // base space — otherwise r2(-portion × ratio) drift would mint a
          // phantom sys:fx-gain residue on cross-currency entries.
          let remainingBase = acctLeg.amountBase;
          patch.splits.forEach((s, i, arr) => {
            const portion = i === arr.length - 1 ? r2(remaining) : r2(acctLeg.amount * s.fraction);
            remaining = r2(remaining - portion);
            const catBase = i === arr.length - 1 ? r2(-remainingBase) : r2(-portion * ratio);
            remainingBase = r2(remainingBase + catBase);
            legs.push(categoryLeg(undefined, s.categoryId, catBase, base, s.description ?? null));
          });
        }
        if (patch.reviewed) reviewedAt = ts;
        if (patch.tagIdsAdd && patch.tagIdsAdd.length > 0) tagIdsAdd = patch.tagIdsAdd;
        appliedRuleIds = patch.appliedRuleIds;
      }
    }
  }

  await appendResidue(exec, e.ledgerId, base, legs);
  validateShape(kind, legs, await categoryMeta(exec, legs));

  const sp = `pe_${Date.now().toString(36)}${Math.floor(Math.random() * 1e4)}`;
  await exec(`SAVEPOINT ${sp}`);
  try {
    await exec(
      `INSERT INTO entries (id,ledger_id,date,time,description,kind,status,confirmed_at,counterparty_id,refunded_entry_id,source_template_id,notes,applied_rule_ids,reviewed_at,dedup_hash,sealed,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,?)`,
      [entryId, e.ledgerId, e.date, e.time ?? null, description, kind, status,
       status === 'confirmed' ? ts : null, counterpartyId ?? null,
       e.refundedEntryId ?? null, e.sourceTemplateId ?? null, notes,
       appliedRuleIds ? JSON.stringify(appliedRuleIds) : null, reviewedAt,
       dedupHash(e.date, e.time, description, legs), ts, ts],
    );
    await insertPostings(exec, entryId, legs);
    // Rule-added tags land inside the same SAVEPOINT (the entry row exists,
    // so the FK holds; mirrors insertTxRow's post-insert tag writes).
    // tagIdsRemove is irrelevant on a fresh entry — nothing to remove.
    if (tagIdsAdd) {
      for (const tagId of tagIdsAdd) {
        await exec('INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)', [entryId, tagId]);
      }
    }
    await exec('UPDATE entries SET sealed = 1 WHERE id = ?', [entryId]);
    await exec(`RELEASE ${sp}`);
  } catch (err) {
    await exec(`ROLLBACK TO ${sp}`);
    await exec(`RELEASE ${sp}`);
    throw err;
  }
  return { entryId };
}

// --- Convenience wrappers (PR B's mutation cases call these) ----------------

export interface SimpleEntryInput {
  ledgerId: string;
  accountId: string;
  /** Signed, in the account's currency. */
  amount: number;
  date: string;
  description: string;
  categoryId?: string | null;
  kind?: EntryKind;
  time?: string | null;
  notes?: string | null;
  status?: EntryStatus;
  refundedEntryId?: string | null;
  sourceTemplateId?: string | null;
  counterpartyId?: string | null;
  skipRules?: boolean;
  id?: string;
  timestamp?: string;
}

/** One account leg + one auto-balanced category leg — today's addTransaction
 *  shape. Kind defaults to income/expense by sign, like addTransaction. */
export async function postSimple(exec: Exec, s: SimpleEntryInput): Promise<{ entryId: string }> {
  const kind = s.kind ?? (s.amount > 0 ? 'income' : 'expense');
  return postEntry(exec, {
    id: s.id, ledgerId: s.ledgerId, date: s.date, time: s.time ?? null,
    description: s.description, kind, status: s.status, notes: s.notes ?? null,
    counterpartyId: s.counterpartyId, refundedEntryId: s.refundedEntryId ?? null,
    sourceTemplateId: s.sourceTemplateId ?? null, skipRules: s.skipRules, timestamp: s.timestamp,
    legs: [{ accountId: s.accountId, amount: s.amount }],
    autoBalanceCategoryId: s.categoryId ?? null,
  });
}

/** Two account legs (+ auto fx residue) — supersedes createTransfer +
 *  transfer_groups. Per-leg memos carry the directional display labels; the
 *  PR B projection surfaces `memo ?? entry.description` as the Tx merchant. */
export async function postTransfer(exec: Exec, a: {
  ledgerId?: string; fromAccountId: string; toAccountId: string;
  fromAmount: number; toAmount?: number | null; date: string; time?: string | null;
  note?: string | null; sourceTemplateId?: string | null; id?: string; timestamp?: string;
}): Promise<{ entryId: string }> {
  const fromAmount = Math.abs(Number(a.fromAmount));
  if (!fromAmount) throw new Error('Transfer amount must be greater than 0');
  if (a.fromAccountId === a.toAccountId) throw new Error('Pick two different accounts');
  const [from] = await exec('SELECT ledger_id, currency, name FROM accounts WHERE id = ?', [a.fromAccountId]);
  const [to] = await exec('SELECT currency, name FROM accounts WHERE id = ?', [a.toAccountId]);
  if (!from || !to) throw new Error('Account not found');
  const ledgerId = a.ledgerId ?? String(from.ledger_id);
  const fromCurrency = String(from.currency);
  const toCurrency = String(to.currency);

  let toAmount: number;
  if (a.toAmount != null) {
    toAmount = Math.abs(Number(a.toAmount));
    if (!(toAmount > 0)) throw new Error('Received amount must be greater than 0');
    if (fromCurrency === toCurrency && Math.abs(toAmount - fromAmount) > 0.005) {
      throw new Error('Same-currency transfer amounts must match');
    }
  } else {
    toAmount = (await convertToBase(exec, fromAmount, fromCurrency, toCurrency, a.date)).amountBase;
  }

  return postEntry(exec, {
    id: a.id, ledgerId, date: a.date, time: a.time ?? null,
    description: 'Transfer', kind: 'transfer', notes: a.note ?? null,
    counterpartyId: null, skipRules: true,
    sourceTemplateId: a.sourceTemplateId ?? null, timestamp: a.timestamp,
    legs: [
      { accountId: a.fromAccountId, amount: -fromAmount, memo: `Transfer to ${String(to.name)}` },
      { accountId: a.toAccountId, amount: toAmount, memo: `Transfer from ${String(from.name)}` },
    ],
  });
}

/** Account delta against the adjustment equity category — supersedes the
 *  kind='adjustment' row of adjustAccountBalance / reconcileAccount. */
export async function postAdjustment(exec: Exec, a: {
  ledgerId: string; accountId: string; delta: number; date: string; time?: string | null;
  note?: string | null; source?: 'manual' | 'reconcile'; id?: string; timestamp?: string;
}): Promise<{ entryId: string } | null> {
  if (!Number.isFinite(a.delta)) throw new Error('Adjustment must be a number');
  // Zero (or sub-cent) delta = already at target: silent no-op, matching the
  // legacy adjustAccountBalance's `if (delta === 0) return` semantics.
  if (r2(a.delta) === 0) return null;
  const sys = await ensureSystemCategories(exec, a.ledgerId);
  return postEntry(exec, {
    id: a.id, ledgerId: a.ledgerId, date: a.date, time: a.time ?? null,
    description: a.source === 'reconcile' ? 'Reconciliation adjustment' : 'Balance adjustment',
    kind: 'adjustment', notes: a.note ?? null, counterpartyId: null, skipRules: true, timestamp: a.timestamp,
    legs: [{ accountId: a.accountId, amount: r2(a.delta) }],
    autoBalanceCategoryId: sys.adjustment,
  });
}

/** The opening-balance entry (replaces accounts.opening_balance in PR B).
 *  Pre-cleared (it IS the reconcile anchor); zero opening → no entry, null. */
export async function postOpening(exec: Exec, o: {
  ledgerId: string; accountId: string; amount: number; date: string; timestamp?: string;
}): Promise<{ entryId: string } | null> {
  if (r2(o.amount) === 0) return null;
  const id = `open-${o.accountId}`;
  // Idempotent: a replayed migration / double call returns the existing entry
  // instead of tripping the PK constraint.
  const existing = await exec('SELECT id FROM entries WHERE id = ?', [id]);
  if (existing.length) return { entryId: id };
  const sys = await ensureSystemCategories(exec, o.ledgerId);
  const ts = o.timestamp ?? new Date().toISOString();
  return postEntry(exec, {
    id, ledgerId: o.ledgerId, date: o.date,
    description: 'Opening balance', kind: 'opening', counterpartyId: null, skipRules: true, timestamp: ts,
    legs: [{ accountId: o.accountId, amount: r2(o.amount), clearedAt: ts }],
    autoBalanceCategoryId: sys.opening,
  });
}

/** Map a raw postings row back to the ResolvedLeg shape (validation/hashing
 *  over EXISTING legs without a rewrite). */
function rowToResolved(r: Record<string, unknown>): ResolvedLeg {
  return {
    id: String(r.id),
    accountId: r.account_id == null ? null : String(r.account_id),
    categoryId: r.category_id == null ? null : String(r.category_id),
    amount: Number(r.amount),
    currency: String(r.currency),
    amountBase: Number(r.amount_base),
    exchangeRate: Number(r.exchange_rate),
    origAmount: r.orig_amount == null ? null : Number(r.orig_amount),
    origCurrency: r.orig_currency == null ? null : String(r.orig_currency),
    memo: r.memo == null ? null : String(r.memo),
    clearedAt: r.cleared_at == null ? null : String(r.cleared_at),
  };
}

/** current_balance from the postings ledger (opening entry included — there
 *  is no opening_balance seed term). PR B swaps queries/accounts.ts's
 *  recomputeAccount over to this. */
export async function recomputeAccountFromPostings(exec: Exec, accountId: string): Promise<void> {
  const rows = await exec(
    `SELECT COALESCE(SUM(p.amount), 0) AS total
       FROM postings p JOIN entries e ON e.id = p.entry_id
      WHERE p.account_id = ? AND e.status = 'confirmed'`,
    [accountId],
  );
  await exec(
    "UPDATE accounts SET current_balance = ROUND(?, 2), updated_at = datetime('now') WHERE id = ?",
    [Number(rows[0]?.total ?? 0), accountId],
  );
}

export interface EntryPatch {
  date?: string;
  time?: string | null;
  description?: string;
  kind?: EntryKind;
  status?: EntryStatus;
  notes?: string | null;
  counterpartyId?: string | null;
  refundedEntryId?: string | null;
  /** Full replacement of ALL legs. Omit to keep them (a date edit still
   *  re-locks account-leg bases at the new date — the locked-rate invariant).
   *  Callers MUST re-supply each account leg's `clearedAt` (and any pinned
   *  `amountBase`) — omitted fields are reset, silently un-clearing a
   *  reconciled leg or re-deriving a user-pinned rate. */
  legs?: LegInput[];
}

/** The single edit path: unseal → patch header → (maybe) rewrite legs →
 *  reseal → recompute every touched account. Supersedes updateTransaction +
 *  updateTransfer + setTransactionSplits in PR B. */
export async function rebuildEntry(exec: Exec, entryId: string, patch: EntryPatch): Promise<{ touchedAccountIds: string[] }> {
  const [cur] = await exec('SELECT * FROM entries WHERE id = ?', [entryId]);
  if (!cur) return { touchedAccountIds: [] };
  const oldLegs = await exec('SELECT * FROM postings WHERE entry_id = ? ORDER BY sort_order', [entryId]);
  const touched = new Set<string>(
    oldLegs.filter((l) => l.account_id != null).map((l) => String(l.account_id)),
  );

  const ledgerId = String(cur.ledger_id);
  const base = await ledgerBase(exec, ledgerId);
  const date = patch.date ?? String(cur.date);
  const kind = (patch.kind ?? String(cur.kind)) as EntryKind;
  const ts = new Date().toISOString();
  const mustRebuildLegs = patch.legs !== undefined || (patch.date !== undefined && patch.date !== String(cur.date));

  const sp = `re_${Date.now().toString(36)}${Math.floor(Math.random() * 1e4)}`;
  await exec(`SAVEPOINT ${sp}`);
  try {
    await exec('UPDATE entries SET sealed = 0 WHERE id = ?', [entryId]);

    const sets: string[] = [];
    const bind: (string | number | null)[] = [];
    if (patch.date !== undefined) { sets.push('date = ?'); bind.push(patch.date); }
    if (patch.time !== undefined) { sets.push('time = ?'); bind.push(patch.time ?? null); }
    if (patch.description !== undefined) { sets.push('description = ?'); bind.push(patch.description); }
    if (patch.kind !== undefined) { sets.push('kind = ?'); bind.push(patch.kind); }
    if (patch.notes !== undefined) { sets.push('notes = ?'); bind.push(patch.notes ?? null); }
    if (patch.counterpartyId !== undefined) { sets.push('counterparty_id = ?'); bind.push(patch.counterpartyId ?? null); }
    if (patch.refundedEntryId !== undefined) { sets.push('refunded_entry_id = ?'); bind.push(patch.refundedEntryId ?? null); }
    if (patch.status !== undefined && patch.status !== String(cur.status)) {
      sets.push('status = ?');
      bind.push(patch.status);
      if (patch.status === 'confirmed') { sets.push('confirmed_at = ?'); bind.push(ts); }
      else sets.push('confirmed_at = NULL');
    }
    sets.push('updated_at = ?');
    bind.push(ts, entryId);
    await exec(`UPDATE entries SET ${sets.join(', ')} WHERE id = ?`, bind);

    let rebuiltLegs: ResolvedLeg[] | null = null;
    if (mustRebuildLegs) {
      let inputs: LegInput[];
      if (patch.legs !== undefined) {
        inputs = patch.legs;
      } else {
        // Keep the existing legs, dropping any prior fx residue (it embodies
        // the OLD date's rates; appendResidue re-derives it below). Account
        // legs intentionally omit amountBase so resolveLegs re-locks them.
        const fxRows = await exec("SELECT id FROM categories WHERE ledger_id = ? AND system = 'fx'", [ledgerId]);
        const fxId = fxRows[0] ? String(fxRows[0].id) : null;
        inputs = oldLegs
          .filter((r) => r.category_id == null || String(r.category_id) !== fxId)
          .map((r): LegInput =>
            r.account_id != null
              ? {
                  id: String(r.id), accountId: String(r.account_id), amount: Number(r.amount),
                  origAmount: r.orig_amount == null ? null : Number(r.orig_amount),
                  origCurrency: r.orig_currency == null ? null : String(r.orig_currency),
                  clearedAt: r.cleared_at == null ? null : String(r.cleared_at),
                  memo: r.memo == null ? null : String(r.memo),
                }
              : {
                  id: String(r.id), categoryId: r.category_id == null ? null : String(r.category_id),
                  amountBase: Number(r.amount_base), memo: r.memo == null ? null : String(r.memo),
                });
      }
      await exec('DELETE FROM postings WHERE entry_id = ?', [entryId]);
      const resolved = await resolveLegs(exec, ledgerId, date, base, inputs);
      if (patch.legs === undefined) {
        // Date-only re-lock: account legs were re-locked at the new date;
        // kept category legs (incl. opening/adjustment equity legs — only fx
        // was dropped) scale proportionally so the category side follows the
        // re-locked figure with split proportions preserved. Rounding dust
        // lands on the fx leg via appendResidue below.
        const oldSum = oldLegs
          .filter((r) => r.account_id != null)
          .reduce((s, r) => s + Number(r.amount_base), 0);
        const newSum = resolved
          .filter((l) => l.accountId != null)
          .reduce((s, l) => s + l.amountBase, 0);
        const scale = oldSum !== 0 ? newSum / oldSum : 1;
        for (const l of resolved) {
          if (l.accountId == null) {
            l.amountBase = r2(l.amountBase * scale);
            l.amount = l.amountBase; // category legs keep amount == amount_base (I9)
          }
        }
      }
      await appendResidue(exec, ledgerId, base, resolved);
      validateShape(kind, resolved, await categoryMeta(exec, resolved));
      await insertPostings(exec, entryId, resolved);
      for (const l of resolved) if (l.accountId != null) touched.add(l.accountId);
      rebuiltLegs = resolved;
    }

    if (!mustRebuildLegs && patch.kind !== undefined && patch.kind !== String(cur.kind)) {
      // A kind-only edit must still satisfy I7 — the seal trigger checks
      // balance, not kind↔shape, so validate against the existing legs.
      const current = oldLegs.map(rowToResolved);
      validateShape(kind, current, await categoryMeta(exec, current));
    }

    // Re-stamp the dedup hash from the entry's EFFECTIVE content — an edited
    // entry must collide (or not) on what it now says, not what it once said.
    // Editing an entry into an exact duplicate of another trips the UNIQUE
    // index right here, rolling the whole edit back.
    const effTime = patch.time !== undefined ? patch.time ?? null : cur.time == null ? null : String(cur.time);
    const effDesc = patch.description !== undefined ? patch.description : cur.description == null ? '' : String(cur.description);
    const hashLegs = rebuiltLegs ?? oldLegs.map(rowToResolved);
    await exec('UPDATE entries SET dedup_hash = ? WHERE id = ?', [dedupHash(date, effTime, effDesc, hashLegs), entryId]);

    await exec('UPDATE entries SET sealed = 1 WHERE id = ?', [entryId]);
    await exec(`RELEASE ${sp}`);
  } catch (err) {
    await exec(`ROLLBACK TO ${sp}`);
    await exec(`RELEASE ${sp}`);
    throw err;
  }

  for (const id of touched) await recomputeAccountFromPostings(exec, id);
  return { touchedAccountIds: [...touched] };
}

/** Delete the whole entry (postings cascade; the sealed DELETE guard passes
 *  because the parent row goes first), then recompute the touched accounts.
 *  In PR B this is the one delete path — deleting any leg's Tx.id removes the
 *  entire entry, killing the orphan-transfer-leg bug class (F1). */
export async function deleteEntry(exec: Exec, entryId: string): Promise<{ touchedAccountIds: string[] }> {
  const rows = await exec(
    'SELECT DISTINCT account_id AS a FROM postings WHERE entry_id = ? AND account_id IS NOT NULL',
    [entryId],
  );
  await exec('DELETE FROM entries WHERE id = ?', [entryId]);
  const ids = rows.map((r) => String(r.a)).sort();
  for (const id of ids) await recomputeAccountFromPostings(exec, id);
  return { touchedAccountIds: ids };
}

export interface EntryRef {
  entryId: string;
  postingId: string | null;
  accountId: string | null;
}

/** Boundary id resolver: the client's Tx.id is an ACCOUNT-POSTING id (design
 *  doc §4.2); server code accepts either a posting id or an entry id. */
export async function resolveEntryRef(exec: Exec, id: string): Promise<EntryRef | null> {
  const [p] = await exec('SELECT id, entry_id, account_id FROM postings WHERE id = ?', [id]);
  if (p) {
    return {
      entryId: String(p.entry_id),
      postingId: String(p.id),
      accountId: p.account_id == null ? null : String(p.account_id),
    };
  }
  const [en] = await exec('SELECT id FROM entries WHERE id = ?', [id]);
  if (!en) return null;
  const [leg] = await exec(
    'SELECT id, account_id FROM postings WHERE entry_id = ? AND account_id IS NOT NULL ORDER BY sort_order LIMIT 1',
    [id],
  );
  return {
    entryId: id,
    postingId: leg ? String(leg.id) : null,
    accountId: leg?.account_id == null ? null : String(leg.account_id),
  };
}

export interface AuditProblem {
  code: 'unsealed' | 'unbalanced' | 'too-few-legs' | 'no-account-leg' | 'currency-mismatch'
      | 'cross-ledger' | 'base-identity' | 'kind-shape' | 'trial-balance' | 'balance-drift';
  entryId?: string;
  detail: string;
}

/** The audit-summary shape carried by /api/db-info, the backup-provider
 *  context, and the Settings ▸ Audit Row. One alias so all three reference
 *  the same field set. */
export interface DbAudit {
  problems: AuditProblem[];
  problemCount: number;
  checkedAt: string;
}

/** Read-only semantic sweep over the entries ledger (design doc §3.3 / I8).
 *  Post-cutover, postings drive accounts.current_balance via the post-insert
 *  `tr_post_balance` trigger (entries-schema.ts) plus explicit
 *  `recomputeAccountFromPostings` calls on edits/deletes, so the cache-vs-
 *  derived check is on by default. Pass `checkBalances: false` only when
 *  intentionally exercising the cache (e.g. a fixture that deliberately
 *  seeds drift to verify detection). */
export async function auditLedger(exec: Exec, ledgerId?: string, opts: { checkBalances?: boolean } = {}): Promise<AuditProblem[]> {
  const checkBalances = opts.checkBalances ?? true;
  const problems: AuditProblem[] = [];
  const scope = ledgerId ? 'AND e.ledger_id = ?' : '';
  const bind = ledgerId ? [ledgerId] : [];

  for (const r of await exec(`SELECT e.id FROM entries e WHERE e.sealed = 0 ${scope}`, bind)) {
    problems.push({ code: 'unsealed', entryId: String(r.id), detail: 'entry was never sealed (torn write)' });
  }
  for (const r of await exec(
    `SELECT e.id, ROUND(SUM(p.amount_base), 2) AS s FROM entries e JOIN postings p ON p.entry_id = e.id
      WHERE 1=1 ${scope} GROUP BY e.id HAVING ROUND(SUM(p.amount_base), 2) != 0`, bind)) {
    problems.push({ code: 'unbalanced', entryId: String(r.id), detail: `postings sum to ${r.s}, not 0` });
  }
  for (const r of await exec(
    `SELECT e.id, COUNT(p.id) AS n, SUM(CASE WHEN p.account_id IS NOT NULL THEN 1 ELSE 0 END) AS a
       FROM entries e LEFT JOIN postings p ON p.entry_id = e.id
      WHERE 1=1 ${scope} GROUP BY e.id HAVING n < 2 OR a < 1`, bind)) {
    problems.push({
      code: Number(r.a) < 1 ? 'no-account-leg' : 'too-few-legs',
      entryId: String(r.id),
      detail: `${r.n} postings, ${r.a} account legs`,
    });
  }
  for (const r of await exec(
    `SELECT p.id, e.id AS eid FROM postings p JOIN entries e ON e.id = p.entry_id JOIN accounts a ON a.id = p.account_id
      WHERE p.currency != a.currency ${scope}`, bind)) {
    problems.push({ code: 'currency-mismatch', entryId: String(r.eid), detail: `posting ${r.id} not in its account's currency` });
  }
  for (const r of await exec(
    `SELECT p.id, e.id AS eid FROM postings p JOIN entries e ON e.id = p.entry_id
       LEFT JOIN accounts a ON a.id = p.account_id
       LEFT JOIN categories c ON c.id = p.category_id
      WHERE ((p.account_id IS NOT NULL AND a.ledger_id != e.ledger_id)
          OR (p.category_id IS NOT NULL AND c.ledger_id != e.ledger_id)) ${scope}`, bind)) {
    problems.push({ code: 'cross-ledger', entryId: String(r.eid), detail: `posting ${r.id} references another ledger` });
  }
  for (const r of await exec(
    `SELECT p.id, e.id AS eid FROM postings p JOIN entries e ON e.id = p.entry_id JOIN ledgers l ON l.id = e.ledger_id
      WHERE p.currency = l.base_currency AND ROUND(p.amount - p.amount_base, 2) != 0 ${scope}`, bind)) {
    problems.push({ code: 'base-identity', entryId: String(r.eid), detail: `posting ${r.id}: amount != amount_base in the base currency (I9)` });
  }
  // I7 kind↔shape: count account legs / plain-category legs / equity legs per
  // entry and compare against the kind's contract.
  for (const r of await exec(
    `SELECT e.id, e.kind,
            SUM(CASE WHEN p.account_id IS NOT NULL THEN 1 ELSE 0 END) AS acct,
            SUM(CASE WHEN p.account_id IS NULL AND COALESCE(c.kind, '') != 'equity' THEN 1 ELSE 0 END) AS plain,
            SUM(CASE WHEN COALESCE(c.kind, '') = 'equity' AND c.system = 'opening'    THEN 1 ELSE 0 END) AS eq_open,
            SUM(CASE WHEN COALESCE(c.kind, '') = 'equity' AND c.system = 'adjustment' THEN 1 ELSE 0 END) AS eq_adj,
            SUM(CASE WHEN COALESCE(c.kind, '') = 'equity' AND c.system = 'fx'         THEN 1 ELSE 0 END) AS eq_fx,
            SUM(CASE WHEN p.account_id IS NOT NULL AND p.amount <= 0 THEN 1 ELSE 0 END) AS neg_acct
       FROM entries e JOIN postings p ON p.entry_id = e.id LEFT JOIN categories c ON c.id = p.category_id
      WHERE 1=1 ${scope} GROUP BY e.id`, bind)) {
    const kind = String(r.kind);
    const acct = Number(r.acct);
    const plain = Number(r.plain);
    const eqOpen = Number(r.eq_open);
    const eqAdj = Number(r.eq_adj);
    const eqFx = Number(r.eq_fx);
    const negAcct = Number(r.neg_acct);
    const bad =
      (kind === 'transfer' && (acct !== 2 || plain > 0 || eqOpen + eqAdj > 0)) ||
      (kind === 'opening' && (acct !== 1 || plain > 0 || eqOpen < 1 || eqAdj > 0)) ||
      (kind === 'adjustment' && (acct !== 1 || plain > 0 || eqAdj < 1 || eqOpen > 0)) ||
      (kind === 'refund' && negAcct > 0) ||
      (['income', 'expense', 'refund'].includes(kind) && (acct !== 1 || plain < 1 || eqOpen + eqAdj > 0));
    if (bad) {
      problems.push({
        code: 'kind-shape', entryId: String(r.id),
        detail: `kind=${kind} but shape is acct=${acct} plain=${plain} eq=[${eqOpen},${eqAdj},${eqFx}]`,
      });
    }
  }
  const tb = await exec(
    `SELECT e.ledger_id AS lid, ROUND(SUM(p.amount_base), 2) AS s
       FROM postings p JOIN entries e ON e.id = p.entry_id WHERE 1=1 ${scope} GROUP BY e.ledger_id`, bind);
  for (const r of tb) {
    if (Number(r.s) !== 0) problems.push({ code: 'trial-balance', detail: `ledger ${r.lid} trial balance is ${r.s}, not 0` });
  }
  if (checkBalances) {
    for (const r of await exec(
      `SELECT * FROM (
         SELECT a.id, a.current_balance AS cached, ROUND(COALESCE((
                  SELECT SUM(p.amount) FROM postings p JOIN entries e ON e.id = p.entry_id
                   WHERE p.account_id = a.id AND e.status = 'confirmed'), 0), 2) AS derived
           FROM accounts a ${ledgerId ? 'WHERE a.ledger_id = ?' : ''}
       ) WHERE ROUND(cached - derived, 2) != 0`, bind)) {
      problems.push({ code: 'balance-drift', detail: `account ${r.id}: cached ${r.cached} vs derived ${r.derived}` });
    }
  }
  return problems;
}
