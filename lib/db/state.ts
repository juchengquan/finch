// The persistence bridge between the Zustand store and the relational SQLite
// database. The store stays the in-memory working model; the database is its
// persisted, queryable form. `serializeState` writes the store into a fresh
// relational DB and exports the bytes (for OPFS/file); `deserializeState`
// reads those bytes back into the store shape.
//
// Reference entities (ledgers/accounts/categories/…) come from the static seed;
// the store's transactions become real rows; the remaining store slices
// (pending/recurring/overrides) live in the transitional `app_state` table
// until their own phase migrates them to real tables.

import { getSqlite3, execFor, type OO1DB } from './sqlite';
import { applySchema, migrate } from './schema';
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
import { splitsByTransaction } from './queries/transactionSplits';
import { listScheduled } from './queries/scheduled';
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
  const [ledgers, accounts, accountGroups, namedBudgets, budgetGroups, categories, counterparties, exchangeRates, tags, tagMap, scheduled] =
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
    ]);
  const mobileTabIds = await readMobileTabIds(exec);
  const displayCurrencyByLedger = await readDisplayCurrencyByLedger(exec);
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
    scheduled,
    mobileTabIds,
    displayCurrencyByLedger,
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

/** Serialise store state into portable relational `.db` bytes. */
export async function serializeState(state: PersistState): Promise<Uint8Array> {
  const sqlite3 = await getSqlite3();
  const db = new sqlite3.oo1.DB(':memory:') as unknown as OO1DB;
  try {
    const exec = execFor(db);
    await applySchema(exec);
    await buildState(exec, state);
    await migrate(exec, { fresh: true }); // current schema → just stamp the version
    return sqlite3.capi.sqlite3_js_db_export(db as never);
  } finally {
    db.close();
  }
}

/** Parse relational `.db` bytes back into store state. */
export async function deserializeState(bytes: Uint8Array): Promise<ProjectedState> {
  const sqlite3 = await getSqlite3();
  const db = new sqlite3.oo1.DB() as unknown as OO1DB;
  try {
    const p = sqlite3.wasm.allocFromTypedArray(bytes);
    const rc = sqlite3.capi.sqlite3_deserialize(
      db.pointer!,
      'main',
      p,
      bytes.length,
      bytes.length,
      sqlite3.capi.SQLITE_DESERIALIZE_FREEONCLOSE | sqlite3.capi.SQLITE_DESERIALIZE_RESIZEABLE,
    );
    if (rc) throw new Error(`Could not read database (code ${rc})`);
    const exec = execFor(db);
    await applySchema(exec); // ensure newer objects exist on older files
    await migrate(exec, { fresh: false }); // bring older exports up to the current columns
    return await projectState(exec);
  } finally {
    db.close();
  }
}
