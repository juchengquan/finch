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
import { listCategories } from './queries/categories';
import { budgetByCategory } from './queries/budgets';
import { listCounterparties } from './queries/counterparties';
import { listExchangeRates, listDevices } from './queries/system';
import { listGoals } from './queries/goals';
import { listTags, transactionTagMap } from './queries/tags';
import { listSubscriptions, listScheduledItems } from './queries/planning';
import { listRecurring } from './queries/recurring';
import type { Exec, PersistState, ProjectedState } from './repo';
import type { Tx } from '@/lib/store';

const APP_STATE_KEYS = [
  'verifiedExtra',
  'aliasExtra',
] as const;

export async function writeAppState(exec: Exec, state: PersistState): Promise<void> {
  const values: Record<string, unknown> = {
    verifiedExtra: state.verifiedExtra,
    aliasExtra: state.aliasExtra,
  };
  for (const k of APP_STATE_KEYS) {
    await exec('INSERT OR REPLACE INTO app_state (key,value) VALUES (?,?)', [k, JSON.stringify(values[k])]);
  }
}

async function readAppState(exec: Exec): Promise<Omit<PersistState, 'transactions'>> {
  const rows = await exec('SELECT key, value FROM app_state');
  const m = new Map(rows.map((r) => [String(r.key), r.value == null ? null : JSON.parse(String(r.value))]));
  return {
    verifiedExtra: (m.get('verifiedExtra') as PersistState['verifiedExtra']) ?? [],
    aliasExtra: (m.get('aliasExtra') as PersistState['aliasExtra']) ?? {},
  };
}

/** Apply the store's counterparty override slices onto the real table. */
async function applyCounterpartyOverrides(
  exec: Exec,
  verifiedExtra: string[],
  aliasExtra: Record<string, string[]>,
): Promise<void> {
  for (const id of verifiedExtra) {
    await exec('UPDATE counterparties SET is_verified = 1 WHERE id = ?', [id]);
  }
  for (const [id, extra] of Object.entries(aliasExtra)) {
    const rows = await exec('SELECT aliases FROM counterparties WHERE id = ?', [id]);
    if (!rows[0]) continue;
    const merged: string[] = rows[0].aliases ? (JSON.parse(String(rows[0].aliases)) as string[]) : [];
    for (const a of extra) if (!merged.includes(a)) merged.push(a);
    await exec('UPDATE counterparties SET aliases = ? WHERE id = ?', [JSON.stringify(merged), id]);
  }
}

/** Build a complete relational DB (in the given connection) from store state. */
export async function buildState(exec: Exec, state: PersistState): Promise<void> {
  await exec('BEGIN');
  try {
    await seedReference(exec);
    await insertTransactions(exec, state.transactions);
    await seedTransactionTags(exec);
    await applyCounterpartyOverrides(exec, state.verifiedExtra, state.aliasExtra);
    await writeAppState(exec, state);
    await exec('COMMIT');
  } catch (err) {
    await exec('ROLLBACK');
    throw err;
  }
}

/** Read the full app state (persisted slices + reference/derived data). */
export async function projectState(exec: Exec): Promise<ProjectedState> {
  const txRows = await exec("SELECT * FROM transactions WHERE status != 'cancelled' ORDER BY date DESC, time DESC");
  const transactions: Tx[] = txRows.map(rowToTx);
  const rest = await readAppState(exec);
  const [accounts, budgets, categories, counterparties, exchangeRates, devices, goals, tags, tagMap, subscriptions, scheduledItems, recurring] =
    await Promise.all([
      listAccounts(exec),
      budgetByCategory(exec),
      listCategories(exec),
      listCounterparties(exec),
      listExchangeRates(exec),
      listDevices(exec),
      listGoals(exec),
      listTags(exec),
      transactionTagMap(exec),
      listSubscriptions(exec),
      listScheduledItems(exec),
      listRecurring(exec),
    ]);
  for (const t of transactions) {
    const ids = tagMap[t.id];
    if (ids) t.tags = ids;
  }
  return {
    transactions,
    ...rest,
    accounts,
    budgetByCategory: budgets,
    categories,
    counterparties,
    exchangeRates,
    devices,
    goals,
    tags,
    subscriptions,
    scheduledItems,
    recurring,
  };
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
