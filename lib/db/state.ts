// The persistence bridge between the Zustand store and the relational SQLite
// database. The store stays the in-memory working model; the database is its
// persisted, queryable form.
//
// Reference entities (ledgers/accounts/categories/…) come from the static seed;
// the store's transactions become real rows; the remaining store slices
// (pending/recurring/overrides) live in the transitional `app_state` table
// until their own phase migrates them to real tables.

import { seedReference, insertTransactions, seedTransactionTags } from './core/seed';
import { enrichLegTxs } from './queries/transactions';
import { listAccounts } from './queries/accounts';
import { listAccountGroups } from './queries/accountGroups';
import { listCategories } from './queries/categories';
import { listBudgets } from './queries/budgets';
import { listBudgetGroups } from './queries/budgetGroups';
import { listCounterparties } from './queries/counterparties';
import { listLedgers } from './queries/ledgers';
import { listExchangeRates } from './queries/system';
import { listTags } from './queries/tags';
import { listRules } from './queries/rules';
import { listScheduled } from './queries/scheduled';
import { listHoldings } from './queries/holdings';
import { listAttachments } from './queries/attachments';
import { getAppState } from './queries/appState';
import type { Exec, PersistState, ProjectedState } from './core/repo';
import type { Tx } from '@/lib/store';

/** Build a complete relational DB (in the given connection) from store state. */
export async function buildState(exec: Exec, state: PersistState): Promise<void> {
  await exec('BEGIN');
  try {
    await seedReference(exec);
    await insertTransactions(exec, state.transactions);
    await seedTransactionTags(exec);
    await exec('COMMIT');
  } catch (err) {
    await exec('ROLLBACK');
    throw err;
  }
}

/** Read the full app state (reference/derived data + the live transactions). */
export async function projectState(exec: Exec): Promise<ProjectedState> {
  // Load account postings joined to their entry headers (opening excluded).
  const BASE_SELECT = `
    SELECT p.id AS pid, p.account_id AS p_account, p.amount AS p_amount, p.amount_base AS p_base,
           p.currency AS p_ccy, p.orig_amount, p.orig_currency, p.cleared_at AS p_cleared, p.memo AS p_memo,
           e.id AS eid, e.ledger_id, e.date, e.time, e.description, e.kind, e.status, e.counterparty_id,
           e.refunded_entry_id, e.source_template_id, e.notes, e.applied_rule_ids, e.reviewed_at,
           e.created_at AS e_created_at
      FROM postings p JOIN entries e ON e.id = p.entry_id
     WHERE p.account_id IS NOT NULL AND e.kind != 'opening'
     ORDER BY e.date DESC, e.time DESC, e.created_at DESC, p.sort_order
  `;
  const txRawRows = await exec(BASE_SELECT, []);

  // Map each raw row into a partial Tx (category/splits/tags filled by enrichLegTxs).
  const partials: Tx[] = txRawRows.map((r) => {
    const amount = Number(r.p_base);
    const nativeAmount = Number(r.orig_amount ?? r.p_amount);
    const currency = r.orig_currency != null ? String(r.orig_currency)
      : r.p_ccy != null ? String(r.p_ccy) : undefined;
    return {
      id: String(r.pid),
      merchant: String(r.p_memo ?? r.description ?? ''),
      category: null,
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
      sourceTemplateId: r.source_template_id == null ? undefined : String(r.source_template_id),
      refundedTransactionId: r.refunded_entry_id == null ? undefined : String(r.refunded_entry_id),
      counterpartyId: r.counterparty_id == null ? undefined : String(r.counterparty_id),
      clearedAt: r.p_cleared == null ? null : String(r.p_cleared),
      appliedRuleIds: (() => {
        const raw = r.applied_rule_ids;
        if (raw == null) return undefined;
        try {
          const v = JSON.parse(String(raw));
          return Array.isArray(v) ? v.map(String) : undefined;
        } catch { return undefined; }
      })(),
      reviewedAt: r.reviewed_at == null ? null : String(r.reviewed_at),
    };
  });
  const entryIds = txRawRows.map((r) => String(r.eid));
  const transactions = await enrichLegTxs(exec, partials, entryIds);

  const [ledgers, accounts, accountGroups, namedBudgets, budgetGroups, categories, counterparties, exchangeRates, tags, scheduled, holdings, rules, rawAttachments] =
    await Promise.all([
      listLedgers(exec),
      listAccounts(exec),
      listAccountGroups(exec),
      listBudgets(exec),
      listBudgetGroups(exec),
      listCategories(exec),
      listCounterparties(exec),
      listExchangeRates(exec),
      listTags(exec),
      listScheduled(exec),
      listHoldings(exec),
      listRules(exec),
      listAttachments(exec),
    ]);
  const mobileTabIds = await readMobileTabIds(exec);
  const displayCurrencyByLedger = await readDisplayCurrencyByLedger(exec);
  const backupConfig = await readBackupConfig(exec);

  // Cache canonical merchant names by counterparty id so renames on the
  // catalog follow history without touching `entries.description`.
  const cpNameById = new Map(counterparties.map((c) => [c.id, c.name]));
  for (const t of transactions) {
    if (t.counterpartyId) {
      const canonical = cpNameById.get(t.counterpartyId);
      if (canonical) t.merchant = canonical;
    }
  }

  // Remap attachment transactionId from entry_id to account-posting id.
  // The client keys attachments by Tx.id (= account-posting id). Build a map
  // entry_id → first account-posting id (by sort_order) from the raw rows.
  const entryToPostingId = new Map<string, string>();
  for (const r of txRawRows) {
    const eid = String(r.eid);
    if (!entryToPostingId.has(eid)) entryToPostingId.set(eid, String(r.pid));
  }
  const attachments = rawAttachments.map((a) => {
    const postingId = entryToPostingId.get(a.transactionId);
    return postingId ? { ...a, transactionId: postingId } : a;
  });

  return {
    transactions,
    ledgers,
    accounts,
    accountGroups,
    budgets: namedBudgets,
    budgetGroups,
    categories,
    counterparties,
    exchangeRates,
    tags,
    holdings,
    scheduled,
    rules,
    attachments,
    mobileTabIds,
    displayCurrencyByLedger,
    backupConfig,
  };
}

// The mobile bottom-bar section ids, stored as a JSON array in app_state. Returns
// [] when unset/malformed; the client applies its own default.
async function readMobileTabIds(exec: Exec): Promise<string[]> {
  const raw = await getAppState(exec, 'mobileTabs');
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === 'string') : [];
  } catch {
    return [];
  }
}

// Per-ledger display currency, stored as a JSON object (ledgerId → currency) in
// app_state. Returns {} when unset/malformed; the client falls back to each
// ledger's base currency.
async function readDisplayCurrencyByLedger(exec: Exec): Promise<Record<string, string>> {
  const raw = await getAppState(exec, 'displayCurrencyByLedger');
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(parsed)) {
      if (typeof v === 'string') out[k] = v;
    }
    return out;
  } catch {
    return {};
  }
}


// Per-DB backup config. Persisted as JSON under app_state['backupConfig'] so
// it travels with the database (a .finch pack carries it; restoring on
// another device keeps the user's preferences).
//
// Precedence (highest to lowest):
//   1. app_state['backupConfig']                       — what the user picked
//   2. FINCH_BACKUP_MIN_INTERVAL_MS / FINCH_BACKUP_KEEP — env-var fallback
//   3. Hardcoded defaults (1h / 14)                    — final fallback
export interface BackupConfigSlice {
  /** Minimum ms between auto-backups. 0 = on every change; -1 = off
   *  (auto-backup disabled; user can still hit Backup now). */
  frequencyMs: number;
  /** Maximum number of backups kept on disk. */
  retention: number;
}

function envFallbackFrequencyMs(): number {
  const v = Number(process.env.FINCH_BACKUP_MIN_INTERVAL_MS);
  return Number.isFinite(v) && v >= 0 ? Math.trunc(v) : 60 * 60 * 1000;
}

function envFallbackRetention(): number {
  const v = Number(process.env.FINCH_BACKUP_KEEP);
  return Number.isFinite(v) && v > 0 ? Math.trunc(v) : 14;
}

/** Effective backup config = app_state if set, else env-var fallback, else
 *  hardcoded defaults. Exported because the autoBackup runtime in server.ts
 *  reads it too — single source of truth so the Settings UI shows exactly
 *  what's in effect at runtime. */
export async function readBackupConfig(exec: Exec): Promise<BackupConfigSlice> {
  const frequencyDefault = envFallbackFrequencyMs();
  const retentionDefault = envFallbackRetention();
  const raw = await getAppState(exec, 'backupConfig');
  if (!raw) return { frequencyMs: frequencyDefault, retention: retentionDefault };
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return { frequencyMs: frequencyDefault, retention: retentionDefault };
    }
    const freq = Number((parsed as { frequencyMs?: unknown }).frequencyMs);
    const ret = Number((parsed as { retention?: unknown }).retention);
    return {
      frequencyMs: Number.isFinite(freq) ? Math.trunc(freq) : frequencyDefault,
      retention: Number.isFinite(ret) && ret > 0 ? Math.trunc(ret) : retentionDefault,
    };
  } catch {
    return { frequencyMs: frequencyDefault, retention: retentionDefault };
  }
}
