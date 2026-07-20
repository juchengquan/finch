// Builds the relational seed from the app's data/*.json, converting the flat
// mock shapes into the design-doc schema. Existing string ids are reused as PKs
// so the current UI lookups keep working as screens migrate.
//
// Split into reusable parts so persistence (lib/db/state.ts) can rebuild a DB
// from arbitrary store state:
//   - seedReference: the static entity tables (ledgers/accounts/categories/…).
//   - insertTransactions: rows from a Tx[] (seed JSON or live store).
//   - seedAppStateDefaults: the transitional store slices (pending/scheduled/…).

import type { Exec } from './repo';
import type { Tx } from '@/lib/store';
import { convertToBase } from '../queries/rates';
import { resolveCounterpartyIdByName } from '../queries/counterparties';
import { ensureSystemCategories, postOpening, recomputeAccountFromPostings } from './entries';
import { insertSealedEntry, appendResidueIfNeeded, type MoveLeg, type MoveHeader } from './sealed-entry';
import { defaultIncludeInNetWorth } from '@/lib/account-types';
import accountsData from '@/data/accounts.json';
import accountGroupsData from '@/data/account-groups.json';
import categoriesData from '@/data/categories.json';
import ledgersData from '@/data/ledgers.json';
import counterpartiesData from '@/data/counterparties.json';
import exchangeRatesData from '@/data/exchange-rates.json';
import goalsData from '@/data/goals.json';
import tagsData from '@/data/tags.json';
import transactionsData from '@/data/transactions.json';
import scheduledData from '@/data/scheduled-templates.json';
import holdingsData from '@/data/holdings.json';

const SEED_TS = '2026-05-26T00:00:00';
const SEED_DATE = '2026-05-26';

const ACCOUNT_TYPE: Record<string, string> = {
  checking: 'savings',
  savings: 'savings',
  credit: 'credit_card',
  invest: 'investment',
  cash: 'cash',
  fx: 'fx',
  virtual: 'virtual',
};

type AccountRow = { id: string; name: string; type: string; group: string; balance: number; color?: string; ledger?: string };
type CategoryRow = { id: string; name: string; parent?: string; budget?: number; icon?: string; color?: string; ledger?: string };
type CounterpartyRow = { id: string; name: string; verified?: number };
type RateRow = { date: string; currency: string; rate: number; source?: string };

const accounts = accountsData as AccountRow[];
const categories = categoriesData as CategoryRow[];
const ledgers = ledgersData as { id: string; name: string; base: string; isDefault: number; color?: string; tagline?: string }[];

const baseOf = (ledgerId: string) => ledgers.find((l) => l.id === ledgerId)?.base ?? 'USD';

// The ledger-base value of a transaction: its `amount`, except foreign rows whose
// base is derived from the exchange_rates table (rate locked at the txn date).
async function baseOfTx(exec: Exec, t: Tx): Promise<{ amountBase: number; rate: number; native: number; currency: string }> {
  const baseCurrency = baseOf(t.ledgerId ?? 'personal');
  const native = t.nativeAmount ?? t.amount;
  const currency = t.currency ?? baseCurrency;
  if (t.nativeAmount != null && currency !== baseCurrency) {
    const conv = await convertToBase(exec, native, currency, baseCurrency, t.date);
    return { amountBase: conv.amountBase, rate: conv.rate, native, currency };
  }
  return { amountBase: t.amount, rate: 1, native, currency };
}

// Each account's opening balance is fixed: the known seed balance minus the sum
// of the *seed* transactions' base amounts. Running balances start there and add
// whatever is actually inserted, so current_balance reflects the live set
// (adds/deletes), not just the original seed.
async function seedOpeningByAccount(exec: Exec): Promise<Map<string, number>> {
  const deltaByAccount = new Map<string, number>();
  for (const t of transactionsData as Tx[]) {
    if (t.pending) continue; // pending rows don't move the balance
    const { amountBase } = await baseOfTx(exec, t);
    deltaByAccount.set(t.account, (deltaByAccount.get(t.account) ?? 0) + amountBase);
  }
  const opening = new Map<string, number>();
  for (const a of accounts) {
    opening.set(a.id, Math.round(((a.balance ?? 0) - (deltaByAccount.get(a.id) ?? 0)) * 100) / 100);
  }
  return opening;
}
const isoDate = (d: string) => d.replace(/\//g, '-');

/** Seed the static reference tables (everything except transactions / app_state). */
export async function seedReference(exec: Exec): Promise<void> {
  for (const l of ledgers) {
    await exec(
      'INSERT INTO ledgers (id,name,base_currency,is_default,color,tagline,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)',
      [l.id, l.name, l.base, l.isDefault ? 1 : 0, l.color ?? null, l.tagline ?? null, SEED_TS, SEED_TS],
    );
  }

  // Every ledger gets its three equity system categories (DOUBLE_ENTRY_PLAN §2.3).
  for (const l of ledgers) await ensureSystemCategories(exec, l.id);

  // Groups are shared across ledgers in the mock; seed them under the default
  // ledger (FK only requires the group row to exist, not a ledger match).
  for (let i = 0; i < accountGroupsData.length; i++) {
    const g = accountGroupsData[i];
    await exec(
      'INSERT INTO account_groups (id,ledger_id,name,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?)',
      [g.id, 'personal', g.name, i, SEED_TS, SEED_TS],
    );
  }

  for (const a of accounts) {
    const ledgerId = a.ledger ?? 'personal';
    const ledgerBase = baseOf(ledgerId);
    // current_balance starts at 0; insertTransactions will post opening entries
    // via postOpening and then recomputeAccountFromPostings to land at the
    // known seed balance.
    await exec(
      'INSERT INTO accounts (id,ledger_id,group_id,name,type,currency,current_balance,color,include_in_net_worth,is_active,created_at,updated_at) VALUES (?,?,?,?,?,?,0,?,?,?,?,?)',
      [a.id, ledgerId, a.group, a.name, ACCOUNT_TYPE[a.type] ?? 'savings', ledgerBase, a.color ?? null, defaultIncludeInNetWorth(ACCOUNT_TYPE[a.type] ?? 'savings'), 1, SEED_TS, SEED_TS],
    );
  }

  for (let i = 0; i < categories.length; i++) {
    const c = categories[i];
    await exec(
      'INSERT INTO categories (id,ledger_id,parent_id,name,kind,icon,color,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [c.id, c.ledger ?? 'personal', c.parent ?? null, c.name, 'expense', c.icon ?? null, c.color ?? null, i, SEED_TS, SEED_TS],
    );
  }

  for (const cp of counterpartiesData as CounterpartyRow[]) {
    await exec(
      'INSERT INTO counterparties (id,name,is_verified,created_at,updated_at) VALUES (?,?,?,?,?)',
      [cp.id, cp.name, cp.verified ? 1 : 0, SEED_TS, SEED_TS],
    );
  }

  for (const r of exchangeRatesData as RateRow[]) {
    await exec(
      'INSERT OR IGNORE INTO exchange_rates (date,currency,rate,source) VALUES (?,?,?,?)',
      [isoDate(r.date), r.currency, r.rate, r.source ?? null],
    );
  }

  // Goals were merged into Budgets as one-shot income budgets ('bud-goal-' ids),
  // shown on the Budgets › Income tab. (The standalone goals table was removed.)
  type GoalRow = { id: string; name: string; target: number; saved: number; eta?: string; hue?: number; ledger?: string };
  for (const g of goalsData as GoalRow[]) {
    await exec(
      `INSERT OR IGNORE INTO budgets
         (id,ledger_id,group_id,name,kind,amount,saved,carry_forward,frequency,start_date,end_date,is_recurring,rollover,warning_pct,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [`bud-goal-${g.id}`, g.ledger ?? 'personal', null, g.name, 'income', g.target, g.saved ?? 0, 0, 'monthly', '2026-05-01', null, 0, 0, 80, SEED_TS, SEED_TS],
    );
  }

  type TagSeed = { id: string; name: string; color?: string; ledger?: string };
  for (const t of (tagsData as { tags: TagSeed[] }).tags) {
    await exec('INSERT OR IGNORE INTO tags (id,ledger_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)', [
      t.id, t.ledger ?? 'personal', t.name, t.color ?? null, SEED_TS, SEED_TS,
    ]);
  }

  // Scheduled templates store real account FKs (like transactions). The mock
  // references accounts by display name, so resolve each name → id here, scoped
  // by ledger; names are guaranteed to match real accounts. next/last run are
  // display labels.
  const acctIdByName = new Map<string, string>();
  for (const a of accounts) acctIdByName.set(`${a.ledger ?? 'personal'}::${a.name.toLowerCase()}`, a.id);
  const acctId = (ledger: string, name: string): string => {
    const id = acctIdByName.get(`${ledger}::${name.toLowerCase()}`);
    if (!id) throw new Error(`seed: scheduled template references unknown account "${name}" in ledger "${ledger}"`);
    return id;
  };
  type SplitSeed = { account: string; pct?: number; abs?: number | null; label?: string };
  type SchedSeed = {
    id: string; name: string; type: string; amount?: number | null; varies?: number;
    frequency: string; dayOfMonth: number; account: string; from?: string; autoPost?: number;
    nextRun?: string; lastRun?: string; splits?: SplitSeed[]; ledger?: string;
  };
  for (const r of scheduledData as SchedSeed[]) {
    const ledgerId = r.ledger ?? 'personal';
    await exec(
      `INSERT OR IGNORE INTO scheduled_templates
        (id,ledger_id,name,description,kind,amount,amount_varies,splits_enabled,account_id,
         from_account_id,category_id,frequency,day_of_month,start_date,
         next_run,last_run,auto_post,is_active,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [
        r.id, ledgerId, r.name, null, r.type, r.amount ?? null, r.varies ? 1 : 0, r.splits?.length ? 1 : 0,
        acctId(ledgerId, r.account), r.from ? acctId(ledgerId, r.from) : null, null, r.frequency, r.dayOfMonth, '2026-05-01',
        r.nextRun ?? null, r.lastRun ?? null, r.autoPost ?? 1, 1, SEED_TS, SEED_TS,
      ],
    );
    const splits = r.splits ?? [];
    for (let i = 0; i < splits.length; i++) {
      const sp = splits[i];
      await exec(
        'INSERT OR IGNORE INTO scheduled_splits (id,template_id,account_id,amount_pct,amount_abs,description,sort_order) VALUES (?,?,?,?,?,?,?)',
        [`${r.id}-s${i}`, r.id, acctId(ledgerId, sp.account), sp.pct ?? null, sp.abs ?? null, sp.label ?? null, i],
      );
    }
  }

  // Seed investment holdings against their accounts. The account already exists
  // above; FKs require nothing further. ledger_id is resolved by looking the
  // account up (we don't want a separate seed JSON to drift from accounts.json).
  type HoldingSeed = {
    id: string; account: string; symbol: string; name?: string; shares: number;
    costBasis: number; currency: string; lastPrice?: number; lastPriceDate?: string; notes?: string;
  };
  const accountLedger = new Map<string, string>();
  for (const a of accounts) accountLedger.set(a.id, a.ledger ?? 'personal');
  for (const h of holdingsData as HoldingSeed[]) {
    const hLedger = accountLedger.get(h.account);
    if (!hLedger) continue; // skip orphan holdings — the JSON references an unknown account
    await exec(
      `INSERT OR IGNORE INTO holdings
         (id,ledger_id,account_id,symbol,name,shares,cost_basis,currency,last_price,last_price_date,notes,created_at,updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`,
      [
        h.id, hLedger, h.account, h.symbol, h.name ?? null, h.shares, h.costBasis, h.currency,
        h.lastPrice ?? null, h.lastPriceDate ?? null, h.notes ?? null, SEED_TS, SEED_TS,
      ],
    );
  }
}

/** Seed the static tag→entry assignments. Must run after entries exist;
 *  OR IGNORE skips rows whose entry is absent. */
export async function seedTransactionTags(exec: Exec): Promise<void> {
  type Assign = { transactionId: string; tagId: string };
  for (const a of (tagsData as { assignments: Assign[] }).assignments) {
    // Guard the FK: OR IGNORE does not suppress foreign-key violations, and
    // buildState may rebuild from an entry set that lacks these seed ids.
    await exec(
      'INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) SELECT ?, ? WHERE EXISTS (SELECT 1 FROM entries WHERE id = ?)',
      [a.transactionId, a.tagId, a.transactionId],
    );
  }
}

const r2 = (n: number) => Math.round(n * 100) / 100;
const r6 = (n: number) => Math.round(n * 1e6) / 1e6;

/**
 * Insert a Tx[] into entries/postings. Maintains per-account chronological
 * ordering (same as before) to preserve id-fidelity. Transfer groups become one
 * entry (entry id = group id); singles become one entry each (entry id = tx id).
 */
export async function insertTransactions(exec: Exec, txs: Tx[]): Promise<void> {
  // Build per-account ordered lists (preserves legacy ordering semantics).
  const byAccount = new Map<string, Tx[]>();
  for (const t of txs) {
    const list = byAccount.get(t.account) ?? [];
    list.push(t);
    byAccount.set(t.account, list);
  }

  // Compute openings (KEEP existing seedOpeningByAccount logic unchanged).
  const opening = await seedOpeningByAccount(exec);

  // Resolve all txs with their base amounts (same as before).
  const allResolved = await Promise.all(
    txs.map(async (t) => ({ t, ledgerId: t.ledgerId ?? 'personal', ...(await baseOfTx(exec, t)) })),
  );
  const resolvedById = new Map(allResolved.map((r) => [r.t.id, r]));

  // Cache system categories per ledger.
  const sysCache = new Map<string, { opening: string; adjustment: string; fx: string }>();
  const getSys = async (ledgerId: string) => {
    if (!sysCache.has(ledgerId)) sysCache.set(ledgerId, await ensureSystemCategories(exec, ledgerId));
    return sysCache.get(ledgerId)!;
  };

  // Track which entry ids have been written (transfer groups).
  const writtenEntryIds = new Set<string>();

  // Cache account currencies (needed for F3 fix).
  const acctCurrencyCache = new Map<string, string>();
  for (const a of accounts) {
    acctCurrencyCache.set(a.id, baseOf(a.ledger ?? 'personal')); // seed accounts inherit ledger base
  }

  // Process accounts in insertion order to emit entries in a consistent order.
  for (const [accountId, list] of byAccount) {
    const ordered = [...list].sort((a, b) =>
      (a.date + (a.time ?? '')).localeCompare(b.date + (b.time ?? '')),
    );

    for (const t of ordered) {
      const r = resolvedById.get(t.id)!;

      if (t.transferGroupId) {
        // --- Transfer group: ONE entry per group ---
        const groupId = t.transferGroupId;
        if (writtenEntryIds.has(groupId)) continue; // already written by the other leg
        writtenEntryIds.add(groupId);

        // Collect both legs of this group (in order).
        const legTxs = txs
          .filter((x) => x.transferGroupId === groupId)
          .sort((a, b) => (a.date + (a.time ?? '')).localeCompare(b.date + (b.time ?? '')));

        if (legTxs.length !== 2) {
          // Not exactly 2 legs: write as singles below (handled by the non-group path).
          writtenEntryIds.delete(groupId);
          // Fall through to the single path for this tx.
        } else {
          const ledgerId = r.ledgerId;
          const base = baseOf(ledgerId);
          const sys = await getSys(ledgerId);

          // Entry header: MAX date, first non-null time, first non-null note.
          const entryDate = legTxs.map((x) => x.date).reduce((a, b) => (a >= b ? a : b));
          const entryTime = legTxs.map((x) => x.time ?? null).find((x) => x != null) ?? null;
          const entryNotes = legTxs.map((x) => x.note ?? null).find((x) => x != null) ?? null;

          // Counterparty: resolved from merchant of first leg.
          const cpId = await resolveCounterpartyIdByName(exec, legTxs[0].merchant);

          // Build account legs — keep each leg's tx id as the POSTING id.
          const legs: MoveLeg[] = [];
          for (const legTx of legTxs) {
            const legR = resolvedById.get(legTx.id)!;
            legs.push({
              id: legTx.id, // id-fidelity: posting id = legacy txn id
              accountId: legTx.account,
              categoryId: null,
              amount: r2(legR.native),
              currency: legR.currency,
              amountBase: r2(legR.amountBase),
              exchangeRate: r6(legR.rate),
              origAmount: null,
              origCurrency: null,
              memo: legTx.merchant ?? null,
              clearedAt: null,
            });
          }

          // FX residue leg.
          appendResidueIfNeeded(legs, sys.fx, base, groupId);

          const hdr: MoveHeader = {
            id: groupId,
            ledgerId,
            date: entryDate,
            time: entryTime,
            description: 'Transfer',
            kind: 'transfer',
            status: legTxs.some((x) => x.pending) ? 'pending' : 'confirmed',
            confirmedAt: legTxs.some((x) => x.pending) ? null : SEED_TS,
            counterpartyId: cpId,
            refundedEntryId: null,
            sourceTemplateId: legTxs.map((x) => x.sourceTemplateId ?? null).find((x) => x != null) ?? null,
            notes: entryNotes,
            appliedRuleIds: null,
            reviewedAt: null,
            createdAt: SEED_TS,
            updatedAt: SEED_TS,
          };

          await insertSealedEntry(exec, hdr, legs);
          continue;
        }
      }

      // --- Single (non-transfer) tx ---
      if (writtenEntryIds.has(t.id)) continue; // already written
      writtenEntryIds.add(t.id);

      const ledgerId = r.ledgerId;
      const base = baseOf(ledgerId);
      const sys = await getSys(ledgerId);

      const cpId = await resolveCounterpartyIdByName(exec, t.merchant);

      // F3 fix: if the tx's native currency differs from the account's currency,
      // re-denominate the account leg into the account's own currency.
      // Seed accounts inherit the ledger base, so acctCcy == base in practice.
      const acctCcy = acctCurrencyCache.get(t.account) ?? base;
      let legAmount = r2(r.native);
      let legCurrency = r.currency;
      let legOrigAmount: number | null = null;
      let legOrigCurrency: string | null = null;
      if (r.currency !== acctCcy) {
        // Native is in a foreign currency; the account needs its own currency.
        // When acctCcy == base: amount_base IS the account-native figure (I9).
        legOrigAmount = r2(r.native);
        legOrigCurrency = r.currency;
        if (acctCcy === base) {
          legAmount = r2(r.amountBase);
        } else {
          // Cross-rate case (unlikely in seed but handled defensively).
          const conv = await convertToBase(exec, r.native, r.currency, acctCcy, t.date);
          legAmount = r2(conv.amountBase);
        }
        legCurrency = acctCcy;
      }

      const acctLeg: MoveLeg = {
        id: t.id, // id-fidelity: account posting id = txn id
        accountId: t.account,
        categoryId: null,
        amount: legAmount,
        currency: legCurrency,
        amountBase: r2(r.amountBase),
        exchangeRate: r6(r.rate),
        origAmount: legOrigAmount,
        origCurrency: legOrigCurrency,
        memo: null,
        clearedAt: null,
      };

      // Category leg: negated base amount (postings convention: category legs
      // are the balancing side). id = `${t.id}-c0` per §8.3.
      const catLeg: MoveLeg = {
        id: `${t.id}-c0`,
        accountId: null,
        categoryId: t.category ?? null,
        amount: r2(-r.amountBase),
        currency: base,
        amountBase: r2(-r.amountBase),
        exchangeRate: 1,
        origAmount: null,
        origCurrency: null,
        memo: null,
        clearedAt: null,
      };

      const legs: MoveLeg[] = [acctLeg, catLeg];
      appendResidueIfNeeded(legs, sys.fx, base, t.id);

      const hdr: MoveHeader = {
        id: t.id,
        ledgerId,
        date: t.date,
        time: t.time ?? null,
        description: t.merchant,
        kind: t.transferGroupId ? 'transfer' : r.amountBase > 0 ? 'income' : 'expense',
        status: t.pending ? 'pending' : 'confirmed',
        confirmedAt: t.pending ? null : SEED_TS,
        counterpartyId: cpId,
        refundedEntryId: t.refundedTransactionId ?? null,
        sourceTemplateId: t.sourceTemplateId ?? null,
        notes: t.note || null,
        appliedRuleIds: null,
        reviewedAt: null,
        createdAt: SEED_TS,
        updatedAt: SEED_TS,
      };

      await insertSealedEntry(exec, hdr, legs);
    }

    // Post opening entry for this account (after entries are inserted so the
    // postings sum already excludes the opening — seedOpeningByAccount uses the
    // known balance minus transaction deltas).
    const open = opening.get(accountId) ?? accounts.find((a) => a.id === accountId)?.balance ?? 0;
    if (r2(open) !== 0) {
      const accRow = accounts.find((a) => a.id === accountId);
      const ledgerId = accRow?.ledger ?? 'personal';
      await postOpening(exec, {
        ledgerId,
        accountId,
        amount: open,
        date: SEED_DATE,
        timestamp: SEED_TS,
      });
    }
  }

  // Accounts that had NO transactions never appeared in byAccount, so their
  // opening balance was never posted. Do a second pass for those.
  for (const a of accounts) {
    if (byAccount.has(a.id)) continue; // already handled above
    const open = opening.get(a.id) ?? a.balance ?? 0;
    if (r2(open) !== 0) {
      const ledgerId = a.ledger ?? 'personal';
      await postOpening(exec, {
        ledgerId,
        accountId: a.id,
        amount: open,
        date: SEED_DATE,
        timestamp: SEED_TS,
      });
    }
  }
}

/** Create a complete fresh database (reference + seed transactions). */
export async function seedDatabase(exec: Exec): Promise<void> {
  await exec('BEGIN');
  try {
    await seedReference(exec);
    await insertTransactions(exec, transactionsData as Tx[]);
    await seedTransactionTags(exec);
    // Recompute every seeded account so current_balance is exact regardless
    // of the trigger-accumulation order (postings may have been inserted in a
    // different order than the trigger assumes).
    for (const a of accounts) {
      await recomputeAccountFromPostings(exec, a.id);
    }
    await exec('COMMIT');
  } catch (err) {
    await exec('ROLLBACK');
    throw err;
  }
}
