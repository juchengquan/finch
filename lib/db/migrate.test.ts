import { test, expect } from 'bun:test';
import { migrate, SCHEMA_VERSION } from '@/lib/db/schema';
import { bareDb } from '@/lib/db/test-utils';
import { needsCutoverSnapshot } from '@/lib/db/server';
import { legacyFixtureDb } from '@/lib/db/cutover.test';
import { auditLedger } from '@/lib/db/entries';
import { projectState } from '@/lib/db/state';
import type { Exec } from '@/lib/db/repo';

const db = async (): Promise<Exec> => (await bareDb()).exec;

const cols = async (exec: Exec, table: string) =>
  (await exec(`PRAGMA table_info(${table})`)).map((r) => String(r.name));

// A database created in the window between the baseline and #66 (the
// unrealized-FX work) carries the *baseline* schema_version yet lacks the
// accounts.opening_balance_base column — #66 added the column without bumping
// the version. These two tests pin both halves of the recovery:
//   1. such a file gets the column added on the next migrate(), and
//   2. a file that already has the column (the common case) is untouched —
//      the additive ALTER is idempotent rather than erroring "duplicate column".
//
// IMPORTANT: the recorded version '2026-06-04T23:59:59Z' means the FULL
// migration chain (06-05 … 06-14) replays on these fixtures. With Fix 1 in
// place (moveLegacyData no-ops when the `transactions` table is absent), the
// 2026-06-14 cutover entry runs harmlessly. The 06-05 ADD COLUMN fires mid-chain
// and is then superseded by the 2026-06-14 accounts-dance that removes
// opening_balance and opening_balance_base entirely. Missing-table statements
// (transactions, transfer_groups, etc.) are swallowed by isAlreadyAppliedError.
// The fixture must be realistic enough for the accounts dance to carry data.

async function staleAccounts(exec: Exec, opts: { withColumn: boolean }): Promise<void> {
  // Minimal ledgers parent so accounts FK is satisfied.
  await exec(`CREATE TABLE ledgers (id TEXT PRIMARY KEY)`);
  await exec(`INSERT INTO ledgers (id) VALUES ('l1')`);

  // Full legacy-shape accounts table so the 2026-06-14 dance can SELECT and
  // INSERT OR IGNORE correctly without a column-mismatch error.
  await exec(
    `CREATE TABLE accounts (
       id                      TEXT PRIMARY KEY,
       ledger_id               TEXT NOT NULL REFERENCES ledgers(id),
       group_id                TEXT,
       name                    TEXT NOT NULL,
       type                    TEXT NOT NULL,
       currency                TEXT NOT NULL DEFAULT 'SGD',
       current_balance         REAL NOT NULL DEFAULT 0,
       opening_balance         REAL NOT NULL DEFAULT 0,
       ${opts.withColumn ? 'opening_balance_base REAL NOT NULL DEFAULT 0,' : ''}
       color                   TEXT,
       sort_order              INTEGER NOT NULL DEFAULT 0,
       include_in_net_worth    INTEGER NOT NULL DEFAULT 1,
       is_active               INTEGER NOT NULL DEFAULT 1,
       archived_at             TEXT,
       last_reconciled_at      TEXT,
       last_reconciled_balance REAL,
       created_at              TEXT NOT NULL,
       updated_at              TEXT NOT NULL
     )`,
  );
  await exec(
    `CREATE TABLE db_metadata (
       id INTEGER PRIMARY KEY, app_name TEXT, schema_version TEXT,
       app_version TEXT, created_at TEXT, updated_at TEXT
     )`,
  );
  // Recorded version is pre-#66: the whole chain (06-05 … 06-14) replays.
  // Missing-table statements are swallowed by isAlreadyAppliedError; the
  // cutover's moveLegacyData no-ops (no transactions table); the accounts
  // dance carries data into the post-cutover shape (opening_balance and
  // opening_balance_base columns removed).
  await exec(
    `INSERT INTO db_metadata (id,app_name,schema_version,app_version,created_at,updated_at)
     VALUES (1,'finch','2026-06-04T23:59:59Z','0.1.0','seed','seed')`,
  );
}

test('migrate carries a pre-#66 database through the full chain to the cutover shape', async () => {
  const exec = await db();
  await staleAccounts(exec, { withColumn: false });
  // Insert a row with all NOT NULL columns satisfied.
  await exec(
    `INSERT INTO accounts (id,ledger_id,name,type,currency,opening_balance,created_at,updated_at)
     VALUES ('a','l1','Acct','savings','SGD',100,'2026-01-01','2026-01-01')`,
  );
  expect(await cols(exec, 'accounts')).not.toContain('opening_balance_base');

  await migrate(exec, { fresh: false });

  // Post-cutover: the 2026-06-14 dance removed both opening_balance columns.
  const postCols = await cols(exec, 'accounts');
  expect(postCols).not.toContain('opening_balance');
  expect(postCols).not.toContain('opening_balance_base');
  // Reconcile column survived the dance.
  expect(postCols).toContain('last_reconciled_at');
  // Row 'a' survived the accounts dance.
  const survivors = await exec(`SELECT id FROM accounts WHERE id = 'a'`);
  expect(survivors.length).toBe(1);
  // Version stamped to the latest.
  const [m] = await exec(`SELECT schema_version FROM db_metadata WHERE id = 1`);
  expect(m.schema_version).toBe(SCHEMA_VERSION);
});

test('migrate is idempotent when opening_balance_base already exists (no duplicate-column error)', async () => {
  const exec = await db();
  await staleAccounts(exec, { withColumn: true });
  // Insert with all NOT NULL columns satisfied; 42 lives in opening_balance_base
  // which is removed by the 2026-06-14 accounts dance — so we don't assert on
  // the 42 value post-migration (the column itself no longer exists by design).
  await exec(
    `INSERT INTO accounts (id,ledger_id,name,type,currency,opening_balance,opening_balance_base,created_at,updated_at)
     VALUES ('a','l1','Acct','savings','SGD',100,42,'2026-01-01','2026-01-01')`,
  );

  await migrate(exec, { fresh: false }); // must not throw (06-05 ADD is idempotent; chain completes)

  // Post-cutover: same shape as Test 1 — opening_balance(_base) gone.
  const postCols = await cols(exec, 'accounts');
  expect(postCols).not.toContain('opening_balance');
  expect(postCols).not.toContain('opening_balance_base');
  // Row 'a' survived (other values intact; 42 is gone with its column by design at 2026-06-14).
  const survivors = await exec(`SELECT id FROM accounts WHERE id = 'a'`);
  expect(survivors.length).toBe(1);
  const [m] = await exec(`SELECT schema_version FROM db_metadata WHERE id = 1`);
  expect(m.schema_version).toBe(SCHEMA_VERSION);
});

// ---------------------------------------------------------------------------
// needsCutoverSnapshot: pure-predicate unit tests (no filesystem involved).
// We extract this from server.ts so the behavior is testable without the full
// driver/file machinery.
// ---------------------------------------------------------------------------

test('needsCutoverSnapshot: true for pre-cutover versions', () => {
  // Any version strictly before the cutover key should trigger a snapshot.
  expect(needsCutoverSnapshot('2026-06-12T00:00:00Z')).toBe(true);
  expect(needsCutoverSnapshot('2026-06-13T00:00:00Z')).toBe(true);
  expect(needsCutoverSnapshot('2026-06-01T20:00:00Z')).toBe(true);
});

test('needsCutoverSnapshot: false for the cutover version and later', () => {
  // At or after the cutover key: no snapshot needed.
  expect(needsCutoverSnapshot('2026-06-14T00:00:00Z')).toBe(false);
  expect(needsCutoverSnapshot('2026-06-15T00:00:00Z')).toBe(false);
  expect(needsCutoverSnapshot(SCHEMA_VERSION)).toBe(false);
});

test('needsCutoverSnapshot: false for an empty recorded version (no metadata row)', () => {
  // An empty string means db_metadata was missing — nothing meaningful to back up.
  expect(needsCutoverSnapshot('')).toBe(false);
});

// ---------------------------------------------------------------------------
// Golden-projection test: run migrate() on a pure legacy fixture DB and verify
// that the full cutover produces a correct, audit-clean double-entry state.
// ---------------------------------------------------------------------------

test('the 2026-06-14 cutover migrates a legacy file end-to-end (golden projection)', async () => {
  // Build a pure legacy fixture (pre-cutover schema_version, no DE tables).
  const { exec, close } = await legacyFixtureDb({ pure: true });
  try {
    // Capture pre-migration account balances (set by the legacy trigger as rows
    // were inserted — these are the figures the DE world must reproduce (except a-main).
    //   a-main:  500(open) + 3000(inc) - 80(tg-x) - 135(tg-xc) - 25.4(gbp-f3→amount_base!) = 3259.6 SGD
    //            §10.2: the legacy trigger used amount_base (-25.4 USD) for the GBP F3 row
    //            (old F3 bug); the cutover recomputes to -34.32 SGD (GBP→SGD). Delta = -8.92.
    //   a-cc:    0 - 120(exp) + 80(tg-x) + 30(refund) - 100(sx) = -110 SGD
    //   a-usd:   200(open) + 100.5(tg-xc) - 37(F3 re-denom) = 263.5 USD
    //   a-plain: 0 - 7(stray/adj) = -7 SGD  [t-pend pending, excluded from trigger]
    const preMigBalances = new Map(
      (await exec('SELECT id, current_balance FROM accounts')).map((r) => [
        String(r.id),
        Number(r.current_balance),
      ]),
    );

    // Run the full migration (applies 2026-06-13 DE tables + 2026-06-14 cutover).
    await migrate(exec, { fresh: false });

    // -------------------------------------------------------------------------
    // 1. Audit clean.
    // -------------------------------------------------------------------------
    const auditProblems = await auditLedger(exec, undefined, { checkBalances: true });
    expect(auditProblems).toEqual([]);

    // -------------------------------------------------------------------------
    // 2. Legacy tables gone, new tables present.
    // -------------------------------------------------------------------------
    const legacyTablesStillPresent = await exec(
      `SELECT name FROM sqlite_master
        WHERE type = 'table'
          AND name IN ('transactions','transfer_groups','transaction_splits',
                       'transaction_tags','transaction_attachments')`,
    );
    expect(legacyTablesStillPresent.length).toBe(0);

    const newTablesPresent = await exec(
      `SELECT name FROM sqlite_master
        WHERE type = 'table'
          AND name IN ('entries','postings','entry_tags','entry_attachments')
        ORDER BY name`,
    );
    expect(newTablesPresent.map((r) => String(r.name)).sort()).toEqual([
      'entries', 'entry_attachments', 'entry_tags', 'postings',
    ]);

    // accounts no longer has the opening_balance / opening_balance_base columns.
    const acctCols = (await exec('PRAGMA table_info(accounts)')).map((r) => String(r.name));
    expect(acctCols).not.toContain('opening_balance');
    expect(acctCols).not.toContain('opening_balance_base');

    // -------------------------------------------------------------------------
    // 3. projectState succeeds; spot-check Tx shape.
    // -------------------------------------------------------------------------
    const state = await projectState(exec);
    const txById = new Map(state.transactions.map((t) => [t.id, t]));

    // 3a. Single income tx: Tx.id === old txn id (id-fidelity: account-leg id = txn id).
    const inc = txById.get('t-inc');
    expect(inc).toBeDefined();
    expect(inc!.kind).toBe('income');

    // 3b. Transfer pair: two Txs sharing transferGroupId === 'tg-x'.
    const txa = txById.get('t-xa');
    const txb = txById.get('t-xb');
    expect(txa).toBeDefined();
    expect(txb).toBeDefined();
    expect(txa!.transferGroupId).toBe('tg-x');
    expect(txb!.transferGroupId).toBe('tg-x');

    // 3c. Refund Tx: refundedTransactionId === original's id.
    const refund = txById.get('t-refund');
    expect(refund).toBeDefined();
    expect(refund!.refundedTransactionId).toBe('t-exp');

    // 3d. Split Tx: splits with ids ['t-sx-s0','t-sx-s1'] and correct signs.
    const split = txById.get('t-sx');
    expect(split).toBeDefined();
    expect(split!.splits).toBeDefined();
    const splitIds = (split!.splits ?? []).map((s) => s.id).sort();
    expect(splitIds).toEqual(['t-sx-s0', 't-sx-s1']);
    // Split amounts (amountBase) are positive (negated from the fixture's -44.4/-29.6
    // to match the postings sign-negation convention: category legs balance the account).
    // The Tx.splits amounts carry the negated category-leg figures back to legacy sign:
    // enrichLegTxs negates them back to "amount in the expense direction" for the UI.
    // See queries/transactions.ts "negate amounts back to legacy parent-signed convention".
    const splitAmounts = (split!.splits ?? []).map((s) => s.amountBase).sort((a, b) => a - b);
    expect(splitAmounts).toEqual([-44.4, -29.6]);

    // 3e. F3 Tx: nativeAmount === -50, currency === 'SGD', account is the USD one.
    const f3 = txById.get('t-f3');
    expect(f3).toBeDefined();
    expect(f3!.account).toBe('a-usd');
    expect(f3!.currency).toBe('SGD');
    expect(f3!.nativeAmount).toBe(-50);

    // 3g. Fix 3 — TRUE 3-currency F3 Tx: GBP expense on SGD account (a-main).
    //     Tx.currency === 'GBP' (the original currency stored as orig_currency → Tx.currency);
    //     Tx.nativeAmount === -20 (the original GBP amount); Tx.account === 'a-main' (SGD).
    //     The posting currency is SGD (re-denominated), and amount_base (-25.4 USD) survived.
    const f3gbp = txById.get('t-f3-gbp');
    expect(f3gbp).toBeDefined();
    expect(f3gbp!.account).toBe('a-main');
    expect(f3gbp!.currency).toBe('GBP');
    expect(f3gbp!.nativeAmount).toBe(-20);
    // Verify the posting: account-leg currency is SGD (account's currency), amount_base = -25.4 USD.
    const [f3gbpPosting] = await exec("SELECT currency, amount_base FROM postings WHERE id = 't-f3-gbp'");
    expect(String(f3gbpPosting.currency)).toBe('SGD');
    expect(Number(f3gbpPosting.amount_base)).toBe(-25.4);

    // 3f. No Tx has kind 'opening' (opening entries are excluded from projectState).
    // Cast through string — 'opening' is not in Tx['kind'] by design; the assertion
    // is a runtime guard confirming the projection filter is correct.
    expect(state.transactions.some((t) => (t.kind as string) === 'opening')).toBe(false);

    // -------------------------------------------------------------------------
    // 4. Balances preserved per account (except a-main — §10.2 exemption).
    //
    // a-usd F3 caveat: the legacy trigger used `amount_base` for the original t-f3 row
    // (currency='SGD' != account currency 'USD' → amount_base = -37). The cutover
    // re-denominates to account currency but since a-usd IS the ledger base,
    // amount = amount_base = -37 USD. Post-cutover balance = 263.5 — exact equality holds.
    //
    // §10.2 — a-main is EXEMPTED: the GBP F3 row (t-f3-gbp) caused the legacy trigger
    // to subtract amount_base (-25.4 USD) as if it were SGD (old F3 bug). The cutover
    // recomputes -20 GBP → SGD via hub: -20 × (1.27/0.74) = -34.32 SGD.
    // Legacy balance: 3259.6 SGD; post-cutover: 3250.68 SGD. Delta = -8.92 SGD.
    // -------------------------------------------------------------------------
    const postMigBalances = new Map(
      (await exec('SELECT id, current_balance FROM accounts')).map((r) => [
        String(r.id),
        Number(r.current_balance),
      ]),
    );
    for (const [id, preBal] of preMigBalances) {
      if (id === 'a-main') continue; // §10.2 — exempted below
      const postBal = postMigBalances.get(id);
      expect(postBal, `account ${id} balance mismatch after migration`).toBe(preBal);
    }
    // §10.2 explicit delta for a-main: legacy -25.4 (amount_base used as SGD by old trigger),
    // cutover -34.32 (GBP→SGD conversion: -20 × (1.27/0.74)). Delta = 8.92 SGD.
    const aMainLegacy = preMigBalances.get('a-main')!;   // 3259.6 SGD (trigger used amount_base)
    const aMainPost   = postMigBalances.get('a-main')!;  // 3250.68 SGD (cutover: -20 GBP → -34.32 SGD)
    expect(Math.round((aMainLegacy - aMainPost) * 100) / 100).toBe(8.92); // §10.2 delta = 8.92 SGD

    // -------------------------------------------------------------------------
    // 5. Transfer-kind category re-kinded to 'expense'.
    //    Fix 4: the fixture now carries a real 'transfer'-kind category
    //    ('old-transfer-cat', added only in pure mode). CATEGORIES_UPGRADE
    //    re-kinds it to 'expense' via the INSERT ... CASE WHEN dance.
    // -------------------------------------------------------------------------
    // Fix 4: assert that the fixture's 'transfer'-kind category was re-kinded.
    const [reKinded] = await exec(`SELECT kind FROM categories WHERE id = 'old-transfer-cat'`);
    expect(reKinded).toBeDefined();
    expect(String(reKinded.kind)).toBe('expense');

    // After upgrade, inserting a NEW 'transfer' kind should fail (CHECK constraint).
    let threw = false;
    try {
      await exec(
        `INSERT INTO categories (id, ledger_id, name, kind, created_at, updated_at)
         VALUES ('cat-test-transfer', 'personal', 'Test', 'transfer', '2026-01-01', '2026-01-01')`,
      );
    } catch {
      threw = true;
    }
    expect(threw).toBe(true);

    // And 'equity' is now valid.
    await exec(
      `INSERT INTO categories (id, ledger_id, name, kind, created_at, updated_at)
       VALUES ('cat-test-equity', 'personal', 'Test Equity', 'equity', '2026-01-01', '2026-01-01')`,
    );
    const [equityCat] = await exec(`SELECT kind FROM categories WHERE id = 'cat-test-equity'`);
    expect(String(equityCat.kind)).toBe('equity');

    // -------------------------------------------------------------------------
    // 6. Re-running migrate() is a no-op (version already stamped; counts stable).
    // -------------------------------------------------------------------------
    const [e1] = await exec('SELECT COUNT(*) AS n FROM entries');
    const [p1] = await exec('SELECT COUNT(*) AS n FROM postings');
    await migrate(exec, { fresh: false });
    const [e2] = await exec('SELECT COUNT(*) AS n FROM entries');
    const [p2] = await exec('SELECT COUNT(*) AS n FROM postings');
    expect(Number(e2.n)).toBe(Number(e1.n));
    expect(Number(p2.n)).toBe(Number(p1.n));

    // -------------------------------------------------------------------------
    // 7. db_metadata.schema_version stamped to SCHEMA_VERSION.
    // -------------------------------------------------------------------------
    const [meta] = await exec('SELECT schema_version FROM db_metadata WHERE id = 1');
    expect(String(meta.schema_version)).toBe(SCHEMA_VERSION);
  } finally {
    close();
  }
});
