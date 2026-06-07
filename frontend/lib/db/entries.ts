// PR A of plans/DOUBLE_ENTRY_PLAN.md §3: the single write chokepoint for the
// entries/postings double-entry core. Nothing outside this module (and the
// PR B migration) writes those tables. Every function assumes the caller
// holds the API route's BEGIN/COMMIT (lib/db/server.ts:392); multi-statement
// writes compose via SAVEPOINT, the recomputeAmountBases idiom.

import { createHash } from 'node:crypto';
import type { Exec } from '@/lib/db/repo';
import type { Tx } from '@/lib/store';
import { convertToBase } from './queries/rates';
import { resolveCounterpartyIdByName } from './queries/counterparties';
import { listActiveRules } from './queries/rules';
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
 *  idx_txn_dedup, whose NULL time never collided (scheduled auto-posts). */
function dedupHash(date: string, time: string | null | undefined, description: string, legs: ResolvedLeg[]): string | null {
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
          patch.splits.forEach((s, i, arr) => {
            const portion = i === arr.length - 1 ? r2(remaining) : r2(acctLeg.amount * s.fraction);
            remaining = r2(remaining - portion);
            legs.push(categoryLeg(undefined, s.categoryId, r2(-portion * ratio), base, s.description ?? null));
          });
        }
        if (patch.reviewed) reviewedAt = ts;
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
    await exec('UPDATE entries SET sealed = 1 WHERE id = ?', [entryId]);
    await exec(`RELEASE ${sp}`);
  } catch (err) {
    await exec(`ROLLBACK TO ${sp}`);
    await exec(`RELEASE ${sp}`);
    throw err;
  }
  return { entryId };
}
