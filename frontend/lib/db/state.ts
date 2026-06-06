// The persistence bridge between the Zustand store and the relational SQLite
// database. The store stays the in-memory working model; the database is its
// persisted, queryable form.
//
// Reference entities (ledgers/accounts/categories/…) come from the static seed;
// the store's transactions become real rows; the remaining store slices
// (pending/recurring/overrides) live in the transitional `app_state` table
// until their own phase migrates them to real tables.

import { seedReference, insertTransactions, seedTransactionTags } from './seed';
import { rowToTx } from './queries/transactions';
import { listAccounts } from './queries/accounts';
import { listAccountGroups } from './queries/accountGroups';
import { listCategories } from './queries/categories';
import { listBudgets } from './queries/budgets';
import { listBudgetGroups } from './queries/budgetGroups';
import { listCounterparties } from './queries/counterparties';
import { listLedgers } from './queries/ledgers';
import { listExchangeRates } from './queries/system';
import { listTags, transactionTagMap } from './queries/tags';
import { listRules } from './queries/rules';
import { splitsByTransaction } from './queries/transactionSplits';
import { listScheduled } from './queries/scheduled';
import { listHoldings } from './queries/holdings';
import { listAttachments } from './queries/attachments';
import { getAppState } from './queries/appState';
import type { Exec, PersistState, ProjectedState } from './repo';
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
  const txRows = await exec('SELECT * FROM transactions ORDER BY date DESC, time DESC');
  const transactions: Tx[] = txRows.map(rowToTx);
  const [ledgers, accounts, accountGroups, namedBudgets, budgetGroups, categories, counterparties, exchangeRates, tags, tagMap, scheduled, holdings, rules, attachments] =
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
      transactionTagMap(exec),
      listScheduled(exec),
      listHoldings(exec),
      listRules(exec),
      listAttachments(exec),
    ]);
  const mobileTabIds = await readMobileTabIds(exec);
  const displayCurrencyByLedger = await readDisplayCurrencyByLedger(exec);
  const backupConfig = await readBackupConfig(exec);
  const splitMap = await splitsByTransaction(exec, transactions.map((t) => t.id));
  // Cache canonical merchant names by counterparty id so renames on the
  // catalog follow history without touching `transactions.description`.
  const cpNameById = new Map(counterparties.map((c) => [c.id, c.name]));
  for (const t of transactions) {
    const ids = tagMap[t.id];
    if (ids) t.tags = ids;
    const splits = splitMap.get(t.id);
    if (splits && splits.length) {
      t.splits = splits.map((s) => ({
        id: s.id,
        categoryId: s.categoryId,
        amount: s.amount,
        amountBase: s.amountBase,
        description: s.description,
      }));
    }
    if (t.counterpartyId) {
      const canonical = cpNameById.get(t.counterpartyId);
      if (canonical) t.merchant = canonical;
    }
  }
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
