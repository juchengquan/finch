import { test, expect } from 'bun:test';
import sqlite3InitModule from '@sqlite.org/sqlite-wasm';
import type { SqlValue } from '@sqlite.org/sqlite-wasm';
import { applySchema } from '@/lib/db/schema';
import { seedDatabase } from '@/lib/db/seed';
import {
  listHoldings,
  getHolding,
  createHolding,
  updateHolding,
  setHoldingPrice,
  deleteHolding,
} from '@/lib/db/queries/holdings';
import type { Exec } from '@/lib/db/repo';

const initSqlite = sqlite3InitModule as unknown as (
  opts?: { print?: () => void; printErr?: () => void },
) => ReturnType<typeof sqlite3InitModule>;

async function seeded(): Promise<Exec> {
  const sqlite3 = await initSqlite({ print() {}, printErr() {} });
  const db = new sqlite3.oo1.DB(':memory:');
  const exec: Exec = async (sql, bind) => {
    const rows: Record<string, SqlValue>[] = [];
    db.exec({ sql, bind: (bind ?? []) as SqlValue[], rowMode: 'object', resultRows: rows });
    return rows;
  };
  await applySchema(exec);
  await seedDatabase(exec);
  return exec;
}

test('listHoldings: seeded brokerage carries 3 positions', async () => {
  const exec = await seeded();
  const rows = await listHoldings(exec, 'personal', 'inv');
  // Sort order is by live value desc (shares × last_price, falling back to
  // cost_basis when no price). Seed: VTI 50×248.50 = 12425, VXUS 80×62.10 = 4968,
  // BND 40×73.85 = 2954. So VTI > VXUS > BND.
  expect(rows.map((h) => h.symbol)).toEqual(['VTI', 'VXUS', 'BND']);
});

test('listHoldings: scoped to account when accountId is passed', async () => {
  const exec = await seeded();
  const all = await listHoldings(exec, 'personal');
  const scoped = await listHoldings(exec, 'personal', 'inv');
  expect(scoped.length).toBe(all.length);
  expect(scoped.every((h) => h.accountId === 'inv')).toBe(true);
});

test('createHolding: insert + getHolding round-trips, symbol upper-cased', async () => {
  const exec = await seeded();
  await createHolding(exec, {
    id: 'h-aapl',
    ledgerId: 'personal',
    accountId: 'inv',
    symbol: 'aapl',
    name: 'Apple Inc.',
    shares: 25,
    costBasis: 4000,
    currency: 'USD',
  });
  const h = await getHolding(exec, 'h-aapl');
  expect(h).not.toBeNull();
  expect(h!.symbol).toBe('AAPL');
  expect(h!.shares).toBe(25);
  expect(h!.costBasis).toBe(4000);
  expect(h!.lastPrice).toBeNull();
});

test('createHolding: defaults currency to the account currency when omitted', async () => {
  const exec = await seeded();
  await createHolding(exec, {
    id: 'h-msft',
    ledgerId: 'personal',
    accountId: 'inv',
    symbol: 'MSFT',
    shares: 10,
    costBasis: 4500,
  });
  const h = await getHolding(exec, 'h-msft');
  expect(h!.currency).toBe('USD'); // `inv` inherits the personal-ledger base (USD)
});

test('updateHolding: edits shares + cost basis; symbol stays upper-cased', async () => {
  const exec = await seeded();
  await updateHolding(exec, 'h-vti', { shares: 60, costBasis: 13500, symbol: 'vti' });
  const h = await getHolding(exec, 'h-vti');
  expect(h!.shares).toBe(60);
  expect(h!.costBasis).toBe(13500);
  expect(h!.symbol).toBe('VTI');
});

test('updateHolding: undefined keys are no-ops; an all-undefined patch is a no-op', async () => {
  const exec = await seeded();
  const before = await getHolding(exec, 'h-vti');
  await updateHolding(exec, 'h-vti', {});
  const after = await getHolding(exec, 'h-vti');
  expect(after).toEqual(before);
});

test('setHoldingPrice: stamps both halves together; null/null clears them', async () => {
  const exec = await seeded();
  await setHoldingPrice(exec, 'h-vti', 260.0, '2026-06-01');
  let h = await getHolding(exec, 'h-vti');
  expect(h!.lastPrice).toBe(260.0);
  expect(h!.lastPriceDate).toBe('2026-06-01');
  await setHoldingPrice(exec, 'h-vti', null, null);
  h = await getHolding(exec, 'h-vti');
  expect(h!.lastPrice).toBeNull();
  expect(h!.lastPriceDate).toBeNull();
});

test('deleteHolding: hard removes the row', async () => {
  const exec = await seeded();
  await deleteHolding(exec, 'h-vti');
  expect(await getHolding(exec, 'h-vti')).toBeNull();
});

test('schema trigger: a direct INSERT into holdings against a non-investment account is rejected', async () => {
  const exec = await seeded();
  // The mutation handler refuses non-investment accounts; the schema trigger
  // is defense-in-depth for paths that bypass the handler (an import script,
  // future bulk loader, a direct SQL exec). `chk` is a savings-type account.
  await expect(
    exec(
      `INSERT INTO holdings (id,ledger_id,account_id,symbol,shares,cost_basis,currency,created_at,updated_at)
       VALUES ('h-bad','personal','chk','AAPL',5,1000,'USD','2026-05-26','2026-05-26')`,
    ),
  ).rejects.toThrow('Holdings can only be added to an investment account');
});

test('schema trigger: UPDATE that moves a holding to a non-investment account is rejected', async () => {
  const exec = await seeded();
  // h-vti currently lives on `inv` (investment). Trying to move it to `chk`
  // (savings) must fail at the trigger.
  await expect(
    exec("UPDATE holdings SET account_id = 'chk' WHERE id = 'h-vti'"),
  ).rejects.toThrow('Holdings can only be added to an investment account');
});

test('account ON DELETE CASCADE: hard-deleting an account takes its holdings', async () => {
  const exec = await seeded();
  // The seed `inv` has transactions, so a hard delete is blocked. Create a fresh
  // account with no transactions to exercise the FK cascade cleanly.
  const now = new Date().toISOString();
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,opening_balance,opening_balance_base,is_active,created_at,updated_at) VALUES ('br2','personal','Brokerage 2','investment','USD',0,0,0,1,?,?)",
    [now, now],
  );
  await createHolding(exec, {
    id: 'h-tmp', ledgerId: 'personal', accountId: 'br2', symbol: 'NVDA', shares: 1, costBasis: 100, currency: 'USD',
  });
  await exec("DELETE FROM accounts WHERE id = 'br2'");
  expect(await getHolding(exec, 'h-tmp')).toBeNull();
});

test('listHoldings hides positions belonging to archived accounts', async () => {
  const exec = await seeded();
  const before = await listHoldings(exec, 'personal', 'inv');
  expect(before.length).toBeGreaterThan(0);
  // Archive the brokerage; its holdings should drop out of the projection.
  await exec("UPDATE accounts SET is_active = 0 WHERE id = 'inv'");
  const after = await listHoldings(exec, 'personal', 'inv');
  expect(after.length).toBe(0);
  // Unarchiving brings them back — the underlying rows are still there.
  await exec("UPDATE accounts SET is_active = 1 WHERE id = 'inv'");
  const restored = await listHoldings(exec, 'personal', 'inv');
  expect(restored.length).toBe(before.length);
});
