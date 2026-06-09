import { test, expect } from 'bun:test';
import { applyMutation } from '@/lib/db/mutate';
import { seededAndAudited } from '@/lib/db/core/test-utils';
import type { Exec } from '@/lib/db/core/repo';
import { convertToBase } from '@/lib/db/queries/rates';
import { recomputeAccount, listAccounts } from '@/lib/db/queries/accounts';
import {
  addTransaction, updateTransaction, confirmPendingWithMerchant,
} from '@/lib/db/queries/transactions';

const balanceOf = async (exec: Exec, id: string) =>
  Number((await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', [id]))[0].b);

test('counterparty FK: addTransaction links exact name (case-insensitive), null on no match', async () => {
  const exec = await seededAndAudited();

  const matched = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -10,
    merchant: 'grab', // lowercase — exists as 'Grab' (cp-02)
    date: '2026-05-25',
  });
  // §2: counterparty_id, description on entries.
  const [m] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [matched]);
  expect(String(m.counterparty_id)).toBe('cp-02');

  const unmatched = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -10,
    merchant: 'Random Shop That Has No Catalog Entry',
    date: '2026-05-25',
  });
  const [u] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [unmatched]);
  expect(u.counterparty_id).toBeNull();
});

test('counterparty FK: renaming a counterparty makes projectState surface the canonical name', async () => {
  const exec = await seededAndAudited();
  const { projectState } = await import('@/lib/db/state');

  // Insert a row that links to Grab (cp-02).
  await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -8,
    merchant: 'Grab', date: '2026-05-25',
  });

  // Rename the catalog entry; projected merchant should follow the new name
  // even though `transactions.description` is unchanged.
  await applyMutation(exec, 'updateCounterparty', { id: 'cp-02', patch: { name: 'Grab Mobility' } });
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.counterpartyId === 'cp-02')!;
  expect(tx).toBeTruthy();
  expect(tx.merchant).toBe('Grab Mobility');
});

test('counterparty FK: updateTransaction re-resolves when merchant text changes', async () => {
  const exec = await seededAndAudited();

  // Start with a row linked to Grab (cp-02).
  const txId = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -8,
    merchant: 'Grab', date: '2026-05-25',
  });
  let [row] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(String(row.counterparty_id)).toBe('cp-02');

  // Rename merchant to a non-catalog string; link should drop to NULL.
  await updateTransaction(exec, txId, { merchant: 'Some One-off Vendor' });
  [row] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(row.counterparty_id).toBeNull();

  // Rename to a known catalog name; link should re-establish.
  await updateTransaction(exec, txId, { merchant: 'Apple' }); // cp-05
  [row] = await exec('SELECT counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(String(row.counterparty_id)).toBe('cp-05');
});

test('counterparty FK: deleting a counterparty leaves linked transactions intact (SET NULL)', async () => {
  const exec = await seededAndAudited();

  const txId = await addTransaction(exec, {
    ledgerId: 'personal', accountId: 'chk', amount: -8,
    merchant: 'Grab', date: '2026-05-25',
  });
  await applyMutation(exec, 'deleteCounterparty', { id: 'cp-02' });
  const [row] = await exec('SELECT counterparty_id, description FROM entries WHERE id = ?', [txId]);
  expect(row.counterparty_id).toBeNull();
  expect(String(row.description)).toBe('Grab');
});

test('addTransaction: exact-name match sets counterparty_id, projection rewrites merchant to canonical', async () => {
  const exec = await seededAndAudited();
  const { projectState } = await import('@/lib/db/state');
  // A raw "Grab" description links to cp-02 at insert time. The projection
  // then surfaces the canonical name on `merchant` (overriding the raw
  // description), and the FK is preserved.
  const entryId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -3,
    merchant: 'Grab',
    date: '2026-05-25',
  });
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [entryId]);
  expect(String(row.description)).toBe('Grab');
  expect(String(row.counterparty_id)).toBe('cp-02');
  // §2: Tx.id = account posting id (≠ entry id); find by counterparty_id + merchant.
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.counterpartyId === 'cp-02' && t.amount === -3)!;
  expect(tx).toBeTruthy();
  expect(tx.counterpartyId).toBe('cp-02');
  expect(tx.merchant).toBe('Grab'); // canonical name == the raw here
});

test('addTransaction: catalog rename rewrites all linked rows on the next projection', async () => {
  const exec = await seededAndAudited();
  const { updateCounterparty } = await import('@/lib/db/queries/counterparties');
  const { projectState } = await import('@/lib/db/state');
  // Insert a row, then rename the counterparty. The row's stored description
  // is untouched (the catalog is the source of truth, not transactions).
  // The projection overrides merchant with the new canonical name on read.
  await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -3,
    merchant: 'Grab',
    date: '2026-05-25',
  });
  await updateCounterparty(exec, 'cp-02', { name: 'Grab Holdings' });
  // §2: Tx.id = account posting id; find by counterparty_id.
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.counterpartyId === 'cp-02' && t.amount === -3)!;
  expect(tx).toBeTruthy();
  expect(tx.merchant).toBe('Grab Holdings');
  expect(tx.counterpartyId).toBe('cp-02');
});

test('addTransaction: unknown name leaves counterparty_id null (no auto-create)', async () => {
  const exec = await seededAndAudited();
  // A brand-new name like "BLUE BOTTLE COFFEE" doesn't match the catalog, so
  // the row is inserted unlinked. The matcher/picker is responsible for
  // creating the counterparty and linking it later (via
  // confirmPendingWithMerchant or a future Add-Expense pre-link).
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -12.5,
    merchant: 'BLUE BOTTLE COFFEE',
    date: '2026-05-25',
  });
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(String(row.description)).toBe('BLUE BOTTLE COFFEE');
  expect(row.counterparty_id).toBeNull();
});

test('addTransaction: explicit counterpartyId links the row to that counterparty', async () => {
  const exec = await seededAndAudited();
  // Pass a raw merchant string that wouldn't match by name. The explicit
  // counterpartyId forces the link, and the projection surfaces the canonical
  // name on `merchant` regardless of the raw description.
  const entryId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -8,
    merchant: 'APPLE.COM/BILL',
    date: '2026-05-25',
    counterpartyId: 'cp-05', // Apple (verified, seeded)
  });
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [entryId]);
  expect(String(row.description)).toBe('APPLE.COM/BILL');
  expect(String(row.counterparty_id)).toBe('cp-05');
  // Projection surfaces the canonical name on the merchant field.
  // §2: Tx.id = account posting id (≠ entry id); find by counterparty_id.
  const { projectState } = await import('@/lib/db/state');
  const projected = await projectState(exec);
  const tx = projected.transactions.find((t) => t.counterpartyId === 'cp-05' && t.amount === -8)!;
  expect(tx).toBeTruthy();
  expect(tx.merchant).toBe('Apple');
  expect(tx.counterpartyId).toBe('cp-05');
});

test('addTransaction: explicit counterpartyId is rejected if it belongs to a different ledger', async () => {
  const exec = await seededAndAudited();
  // Spin up a second ledger + counterparty; passing its id to an
  // addTransaction for the 'personal' ledger must not link.
  await exec(
    "INSERT INTO ledgers (id, name, base_currency, is_default, created_at, updated_at) VALUES ('biz', 'Business', 'SGD', 0, datetime('now'), datetime('now'))",
  );
  const otherCpId = 'cp-other-ledger';
  await exec(
    "INSERT INTO counterparties (id, ledger_id, name, is_verified, created_at, updated_at) VALUES (?, 'biz', ?, 1, datetime('now'), datetime('now'))",
    [otherCpId, 'Foreign Ledger Merchant'],
  );
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -5,
    merchant: 'Raw Merchant String',
    date: '2026-05-25',
    counterpartyId: otherCpId,
  });
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(row.counterparty_id).toBeNull();
  expect(String(row.description)).toBe('Raw Merchant String');
});

test('addTransaction: no counterpartyId + exact name match → auto-resolve', async () => {
  const exec = await seededAndAudited();
  // "Grab" (capitalised) still auto-resolves to cp-02 the legacy way when
  // counterpartyId is omitted.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -3,
    merchant: 'Grab',
    date: '2026-05-25',
  });
  const [row] = await exec('SELECT description, counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(String(row.description)).toBe('Grab');
  expect(String(row.counterparty_id)).toBe('cp-02');
});

test('confirmPendingWithMerchant: links + rewrites description in one round-trip', async () => {
  const exec = await seededAndAudited();
  // Insert a pending row with a raw, munged merchant name.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -8,
    merchant: 'NETFLIX.COM*SUB',
    date: '2026-05-25',
    status: 'pending',
  });
  // Confirm + link to Apple (cp-05). The matcher would never suggest Apple
  // for "NETFLIX.COM*SUB" but the test exercises the wiring directly.
  await confirmPendingWithMerchant(exec, txId, { counterpartyId: 'cp-05' });
  const [row] = await exec(
    'SELECT status, description, counterparty_id, confirmed_at FROM entries WHERE id = ?',
    [txId],
  );
  expect(String(row.status)).toBe('confirmed');
  expect(String(row.description)).toBe('Apple'); // canonical name, not raw
  expect(String(row.counterparty_id)).toBe('cp-05');
  expect(row.confirmed_at).not.toBeNull();
});

test('confirmPendingWithMerchant: newCounterpartyName creates unverified + links', async () => {
  const exec = await seededAndAudited();
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -4.5,
    merchant: 'BLUE BOTTLE COFFEE',
    date: '2026-05-25',
    status: 'pending',
  });
  await confirmPendingWithMerchant(exec, txId, { newCounterpartyName: 'Blue Bottle Coffee' });
  const [row] = await exec('SELECT status, description, counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(String(row.status)).toBe('confirmed');
  expect(String(row.description)).toBe('Blue Bottle Coffee');
  const cpId = String(row.counterparty_id);
  expect(cpId).toMatch(/^cp-/);
  const [cp] = await exec('SELECT name, is_verified FROM counterparties WHERE id = ?', [cpId]);
  expect(String(cp.name)).toBe('Blue Bottle Coffee');
  expect(Number(cp.is_verified)).toBe(0);
});

test('confirmPendingWithMerchant: with no resolution leaves the row confirmed but unlinked', async () => {
  const exec = await seededAndAudited();
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -2,
    merchant: 'ONE OFF MERCHANT',
    date: '2026-05-25',
    status: 'pending',
  });
  await confirmPendingWithMerchant(exec, txId, {});
  const [row] = await exec('SELECT status, description, counterparty_id FROM entries WHERE id = ?', [txId]);
  expect(String(row.status)).toBe('confirmed');
  expect(String(row.description)).toBe('ONE OFF MERCHANT');
  expect(row.counterparty_id).toBeNull();
});

test('updateTransaction: account change moves the row and recomputes both source + destination balances', async () => {
  const exec = await seededAndAudited();
  // Establish a known starting balance.
  await recomputeAccount(exec, 'chk');
  await recomputeAccount(exec, 'sav');
  const startChk = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  const startSav = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'sav')!.balance);
  // Insert a confirmed $50 expense on chk.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -50,
    merchant: 'Moving target',
    date: '2026-05-25',
  });
  await recomputeAccount(exec, 'chk');
  const afterAddChk = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  expect(afterAddChk).toBeCloseTo(startChk - 50, 2);
  // Move it to sav via the dispatcher. Both the source and the destination
  // account should be recomputed; chk's balance rises back to startChk and
  // sav's drops by 50.
  await applyMutation(exec, 'updateTransaction', { id: txId, patch: { account: 'sav' } });
  const finalChk = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  const finalSav = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'sav')!.balance);
  expect(finalChk).toBeCloseTo(startChk, 2);
  expect(finalSav).toBeCloseTo(startSav - 50, 2);
  // §2: account_id on the posting.
  const [row] = await exec('SELECT p.account_id FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [txId]);
  expect(String(row.account_id)).toBe('sav');
});

test('updateTransaction: same-account edit returns null oldAccountId', async () => {
  const exec = await seededAndAudited();
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -10,
    merchant: 'Note change',
    date: '2026-05-25',
  });
  // Patch only the note — the row stays in chk, so oldAccountId is null and
  // the dispatcher's "recompute source account" branch is a no-op.
  const result = await updateTransaction(exec, txId, { note: 'updated' });
  expect(result.oldAccountId).toBeNull();
  // §2: account_id on postings, notes on entries.
  const [prow] = await exec('SELECT p.account_id FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [txId]);
  const [erow] = await exec('SELECT notes FROM entries WHERE id = ?', [txId]);
  expect(String(prow.account_id)).toBe('chk');
  expect(String(erow.notes)).toBe('updated');
});

test('updateTransaction: currency change re-derives amount_base + locks a new rate', async () => {
  const exec = await seededAndAudited();
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -100,
    merchant: 'Currency switch',
    date: '2026-05-25',
  });
  // Same-magnitude form, new currency label. amount_base should be re-derived
  // against the new currency at the same date; the rate is locked.
  // §2: updateTransaction with currency='SGD' on a USD account means the input
  // is in SGD; the posting stores currency='USD' (account currency) and the
  // amount_base is recomputed treating the input as SGD.
  await updateTransaction(exec, txId, { currency: 'SGD' });
  // §5.2: currency='SGD' on a USD account → foreign-currency input path.
  // Posting stores: currency=USD (account), amount=SGD→USD conversion,
  // amount_base=USD (ledger base=USD so same), orig_amount=-100, orig_currency='SGD'.
  const [row] = await exec('SELECT p.amount, p.currency, p.amount_base, p.exchange_rate, p.orig_amount, p.orig_currency FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [txId]);
  // currency stays USD (account currency), amount is the converted USD figure.
  expect(String(row.currency)).toBe('USD');
  const convToUsd = await convertToBase(exec, -100, 'SGD', 'USD', '2026-05-25');
  expect(Number(row.amount)).toBeCloseTo(convToUsd.amountBase, 2);
  // amount_base = converted to USD (=ledger base); same figure since acct ccy == ledger base.
  expect(Number(row.amount_base)).toBeCloseTo(convToUsd.amountBase, 2);
  // §5.2: orig_amount + orig_currency carry the typed foreign input.
  expect(Number(row.orig_amount)).toBe(-100);
  expect(String(row.orig_currency)).toBe('SGD');
});

test('updateTransaction: status flip sets/clears confirmed_at and moves the balance', async () => {
  const exec = await seededAndAudited();
  // Insert a $25 pending expense on chk. Pending rows are excluded from the
  // balance sum, so chk's balance is unchanged after add.
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -25,
    merchant: 'Pending expense',
    date: '2026-05-25',
    status: 'pending',
  });
  await recomputeAccount(exec, 'chk');
  const pendingBal = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  // Confirm via the dispatcher. confirmed_at gets stamped; the dispatch
  // recomputes the account, so the balance drops by 25.
  await applyMutation(exec, 'updateTransaction', { id: txId, patch: { status: 'confirmed' } });
  const confirmedBal = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  expect(confirmedBal).toBeCloseTo(pendingBal - 25, 2);
  const [confirmed] = await exec('SELECT status, confirmed_at FROM entries WHERE id = ?', [txId]);
  expect(String(confirmed.status)).toBe('confirmed');
  expect(confirmed.confirmed_at).not.toBeNull();
  // Demote back to pending. confirmed_at clears; the recompute drops the row
  // from the balance sum, so chk's balance rises back to pendingBal.
  await applyMutation(exec, 'updateTransaction', { id: txId, patch: { status: 'pending' } });
  const demotedBal = Number((await listAccounts(exec, 'personal')).find((a) => a.id === 'chk')!.balance);
  expect(demotedBal).toBeCloseTo(pendingBal, 2);
  const [demoted] = await exec('SELECT status, confirmed_at FROM entries WHERE id = ?', [txId]);
  expect(String(demoted.status)).toBe('pending');
  expect(demoted.confirmed_at).toBeNull();
});

test('updateTransaction: cross-ledger account change is rejected', async () => {
  const exec = await seededAndAudited();
  const txId = await addTransaction(exec, {
    ledgerId: 'personal',
    accountId: 'chk',
    amount: -5,
    merchant: 'Cross-ledger attempt',
    date: '2026-05-25',
  });
  // f-dbs is a family-ledger account (the seed has it under ledger='family').
  // The patch must not silently migrate the row across ledgers — it should
  // throw so the UI surfaces a clear error.
  await expect(updateTransaction(exec, txId, { account: 'f-dbs' })).rejects.toThrow(/different ledger/i);
  // The row's account is unchanged. §2: account_id on postings.
  const [row] = await exec('SELECT p.account_id FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [txId]);
  expect(String(row.account_id)).toBe('chk');
});

test('addTransaction on a foreign-currency account: native balance, ledger-base amount_base', async () => {
  const exec = await seededAndAudited();
  // A JPY account inside the personal (USD) ledger — account currency ≠ ledger base.
  // §2: accounts no longer has opening_balance (opening entries replace that column).
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,1,'2026-05-26','2026-05-26')",
  );
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'jpyw', amount: -10000, currency: 'JPY',
    merchant: 'Konbini', date: '2026-05-13', status: 'confirmed',
  });
  // The balance moves in the ACCOUNT's currency (¥), un-converted.
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-10000, 2);
  // §2: account posting carries orig_amount/orig_currency for native JPY; amount is account-native (JPY).
  const [row] = await exec("SELECT p.amount, p.amount_base, p.currency FROM postings p JOIN entries e ON e.id = p.entry_id WHERE p.account_id='jpyw' AND e.kind != 'opening'");
  expect(Number(row.amount)).toBeCloseTo(-10000, 2); // native (¥) — account currency is JPY
  expect(String(row.currency)).toBe('JPY');
  // amount_base is the LEDGER base (USD) figure for cross-account reporting.
  const expected = await convertToBase(exec, -10000, 'JPY', 'USD', '2026-05-13');
  expect(Number(row.amount_base)).toBeCloseTo(expected.amountBase, 2);
  // ¥ → $ shrinks the magnitude ~150×, so base ≠ native (proves they're distinct).
  expect(Math.abs(Number(row.amount_base))).toBeLessThan(Math.abs(Number(row.amount)));
});

test('recompute keeps a foreign-currency account balance in its own currency', async () => {
  const exec = await seededAndAudited();
  // §2: accounts no longer has opening_balance column.
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,1,'2026-05-26','2026-05-26')",
  );
  const add = (amount: number, date: string) =>
    applyMutation(exec, 'addTransaction', {
      ledgerId: 'personal', accountId: 'jpyw', amount, currency: 'JPY', merchant: 'Konbini', date, status: 'confirmed',
    });
  await add(-10000, '2026-05-13');
  await add(-5000, '2026-05-14');
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-15000, 2); // ¥, summed natively
  // Cancelling routes through recomputeAccount — it must reverse in ¥, not USD.
  // §2: entry id is on entries; use entry_id from postings (kind != opening).
  const [{ id }] = await exec("SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id='jpyw' AND p.amount=-5000 AND e.kind != 'opening'");
  await applyMutation(exec, 'deleteTransaction', { id: String(id) });
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-10000, 2);
});

test('editing a foreign-currency transaction amount reconverts amount_base to ledger base', async () => {
  const exec = await seededAndAudited();
  // §2: accounts no longer has opening_balance column.
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,1,'2026-05-26','2026-05-26')",
  );
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'jpyw', amount: -10000, currency: 'JPY', merchant: 'Konbini', date: '2026-05-13', status: 'confirmed',
  });
  // §2: get the entry id from entries (non-opening).
  const [{ id }] = await exec("SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id='jpyw' AND e.kind != 'opening'");
  await applyMutation(exec, 'updateTransaction', { id: String(id), patch: { amount: -20000 } });
  // The balance reflects the new ¥ amount (native), summed in the account currency.
  expect(await balanceOf(exec, 'jpyw')).toBeCloseTo(-20000, 2);
  // §2: account posting carries amount/amount_base.
  const [row] = await exec('SELECT p.amount, p.amount_base FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL', [String(id)]);
  expect(Number(row.amount)).toBeCloseTo(-20000, 2); // native (¥)
  // amount_base is re-derived in USD (ledger base), not left as the native ¥ figure.
  const expected = await convertToBase(exec, -20000, 'JPY', 'USD', '2026-05-13');
  expect(Number(row.amount_base)).toBeCloseTo(expected.amountBase, 2);
  expect(Math.abs(Number(row.amount_base))).toBeLessThan(Math.abs(Number(row.amount)));
});

test('editing only the date re-locks exchange_rate + amount_base to the new date', async () => {
  const exec = await seededAndAudited();
  // §2: accounts no longer has opening_balance column.
  await exec(
    "INSERT INTO accounts (id,ledger_id,name,type,currency,current_balance,is_active,created_at,updated_at) VALUES ('jpyw','personal','JPY Wallet','cash','JPY',0,1,'2026-05-26','2026-05-26')",
  );
  // Two distinct JPY rates so moving the date measurably changes the lock.
  await applyMutation(exec, 'setExchangeRate', { date: '2026-05-20', currency: 'JPY', rate: 0.0070, source: 'manual' });
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'jpyw', amount: -10000, currency: 'JPY', merchant: 'Konbini', date: '2026-05-13', status: 'confirmed',
  });
  // §2: get entry id from entries (non-opening).
  const [{ id }] = await exec("SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id='jpyw' AND e.kind != 'opening'");
  await applyMutation(exec, 'updateTransaction', { id: String(id), patch: { date: '2026-05-20' } });
  // §2: date on entry; amount/amount_base/exchange_rate on account posting.
  const [e] = await exec('SELECT date FROM entries WHERE id = ?', [String(id)]);
  const [row] = await exec('SELECT amount, amount_base, exchange_rate FROM postings WHERE entry_id = ? AND account_id IS NOT NULL', [String(id)]);
  expect(String(e.date)).toBe('2026-05-20');
  expect(Number(row.amount)).toBeCloseTo(-10000, 2); // native amount untouched
  // The lock follows the row's own date: rate + base re-derived at 2026-05-20.
  // exchange_rate is JPY-account-ccy → JPY (same), base is JPY→USD.
  const expected = await convertToBase(exec, -10000, 'JPY', 'USD', '2026-05-20');
  // Note: for JPY account (currency=JPY), amount = orig_amount and
  // exchange_rate = JPY-to-USD rate directly (no acctCcy intermediate).
  const effectiveRate = Math.abs(Number(row.amount_base)) / Math.abs(Number(row.amount));
  expect(effectiveRate).toBeCloseTo(0.007, 6);
  expect(Number(row.amount_base)).toBeCloseTo(expected.amountBase, 2);
});

test('editing a transaction amount recomputes the account balance', async () => {
  const exec = await seededAndAudited();
  const before = await balanceOf(exec, 'cc'); // -842.18
  await applyMutation(exec, 'updateTransaction', { id: 't01', patch: { amount: -100 } });
  // t01 was -6.75 → -100, so cc drops by the 93.25 difference.
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(before - (100 - 6.75), 2);
});

test('cancelling a transaction reverses its effect on the balance', async () => {
  const exec = await seededAndAudited();
  const before = await balanceOf(exec, 'cc');
  await applyMutation(exec, 'deleteTransaction', { id: 't01' }); // -6.75 expense removed
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(before + 6.75, 2);
});

test('setTransactionSplits validates sum + min-2-rows; categorySpend uses splits', async () => {
  const exec = await seededAndAudited();
  // §2: Pick a confirmed expense from entries. amount/amount_base on the account posting,
  // category on the category posting.
  const [parent] = await exec(
    `SELECT e.id, p.amount, p.amount_base, cp.category_id
     FROM entries e
     JOIN postings p ON p.entry_id = e.id AND p.account_id IS NOT NULL
     LEFT JOIN postings cp ON cp.entry_id = e.id AND cp.account_id IS NULL AND cp.category_id IS NOT NULL
     WHERE e.ledger_id = 'personal' AND e.kind = 'expense' AND e.status = 'confirmed'
     LIMIT 1`,
  );
  expect(parent).toBeDefined();
  const txId = String(parent.id);
  const amt = Number(parent.amount);
  const half = Math.round((amt / 2) * 100) / 100;
  const rest = Math.round((amt - half) * 100) / 100;
  const originalCat = String(parent.category_id);

  // < 2 rows is rejected.
  await expect(
    applyMutation(exec, 'setTransactionSplits', { id: txId, splits: [{ categoryId: 'food', amount: amt }] }),
  ).rejects.toThrow(/two/i);

  // Sum mismatch is rejected.
  await expect(
    applyMutation(exec, 'setTransactionSplits', {
      id: txId,
      splits: [{ categoryId: 'food', amount: amt / 2 }, { categoryId: 'trans', amount: amt / 3 }],
    }),
  ).rejects.toThrow(/sum/i);

  // Two valid rows succeed; categorySpend reflects splits, not the parent.
  const { categorySpend } = await import('@/lib/db/queries/categories');
  await applyMutation(exec, 'setTransactionSplits', {
    id: txId,
    splits: [
      { categoryId: 'food', amount: half },
      { categoryId: 'trans', amount: rest },
    ],
  });
  const after = await categorySpend(exec, 'personal');
  // The parent's original category should no longer carry this tx's amount.
  // Both splits' targets get a non-zero contribution.
  // §2: categorySpend returns the signed amount_base sum (negative for expenses).
  expect(after.food).not.toBe(0);
  expect(after.trans).toBeDefined();
  // §2: splits are category postings (account_id IS NULL) on the entry.
  // Exclude fx-system residue legs (appendResidue may add one to absorb rounding).
  // Sanity: per-row stored amount_base is derived from the parent's locked rate.
  const splitRows = await exec(
    `SELECT p.category_id, p.amount, p.amount_base FROM postings p
     LEFT JOIN categories c ON c.id = p.category_id
     WHERE p.entry_id = ? AND p.account_id IS NULL
       AND (c.system IS NULL OR c.system != 'fx')
     ORDER BY p.sort_order`,
    [txId],
  );
  expect(splitRows.length).toBeGreaterThanOrEqual(2);
  // Category postings balance the account leg (opposite sign).
  // Sum of all postings (account + category) should be ≈ 0.
  const allRows = await exec(
    'SELECT amount_base FROM postings WHERE entry_id = ?',
    [txId],
  );
  const totalBalance = allRows.reduce((s, r) => s + Number(r.amount_base), 0);
  expect(totalBalance).toBeCloseTo(0, 2);

  // Clearing splits restores the parent's category.
  await applyMutation(exec, 'setTransactionSplits', { id: txId, splits: [] });
  // After clearing, the original category should have a non-zero spend value
  // (categorySpend returns signed amounts — negative for expenses).
  const restored = await categorySpend(exec, 'personal');
  expect(restored[originalCat]).toBeDefined();
});

test('bulkRecategorize moves N rows in one statement; categorySpend shifts accordingly', async () => {
  const exec = await seededAndAudited();
  const { categorySpend } = await import('@/lib/db/queries/categories');
  // §2: Pick three confirmed expenses by their entry id; category is on the category posting.
  const ids = (
    await exec(
      "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id AND p.account_id IS NULL AND p.category_id = 'food' WHERE e.ledger_id = 'personal' AND e.kind = 'expense' AND e.status = 'confirmed' ORDER BY e.date DESC LIMIT 3",
    )
  ).map((r) => String(r.id));
  expect(ids.length).toBe(3);
  // Sum the account posting amount_base for those entries.
  const movedSum = (
    await exec(
      `SELECT SUM(p.amount_base) AS s FROM postings p WHERE p.entry_id IN (${ids.map(() => '?').join(',')}) AND p.account_id IS NOT NULL`,
      ids,
    )
  )[0];
  const moved = Math.abs(Number(movedSum.s));
  const before = await categorySpend(exec, 'personal');

  await applyMutation(exec, 'bulkRecategorize', { ids, categoryId: 'misc' });
  const after = await categorySpend(exec, 'personal');

  // Each moved row now has category 'misc'; no category posting keeps the old food link.
  const stillFood = await exec(
    `SELECT COUNT(*) AS c FROM postings WHERE entry_id IN (${ids.map(() => '?').join(',')}) AND category_id = 'food'`,
    ids,
  );
  expect(Number(stillFood[0].c)).toBe(0);
  expect((after['food'] ?? 0)).toBeCloseTo((before['food'] ?? 0) - moved, 2);
  expect((after['misc'] ?? 0)).toBeCloseTo((before['misc'] ?? 0) + moved, 2);
});

test('bulkRecategorize: empty ids is a no-op; null categoryId clears the link', async () => {
  const exec = await seededAndAudited();
  // §2: category is on category postings (account_id IS NULL).
  const beforeCount = Number(
    (await exec("SELECT COUNT(*) AS c FROM postings WHERE category_id = 'food'"))[0].c,
  );
  await applyMutation(exec, 'bulkRecategorize', { ids: [], categoryId: 'misc' });
  expect(
    Number((await exec("SELECT COUNT(*) AS c FROM postings WHERE category_id = 'food'"))[0].c),
  ).toBe(beforeCount);

  // Null: clear the category on a single entry's category posting.
  const [row] = await exec(
    "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id AND p.category_id = 'food' AND p.account_id IS NULL WHERE e.ledger_id = 'personal' LIMIT 1",
  );
  const id = String(row.id);
  await applyMutation(exec, 'bulkRecategorize', { ids: [id], categoryId: null });
  const [after] = await exec('SELECT category_id AS c FROM postings WHERE entry_id = ? AND account_id IS NULL', [id]);
  expect(after.c).toBeNull();
});

test('setCleared toggles cleared_at and is independent of status', async () => {
  const exec = await seededAndAudited();
  // §2: cleared_at is per-leg on postings (not on entries). status is on entries.
  // Resolve entry id; then check the account posting's cleared_at.
  const [row] = await exec(
    "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind NOT IN ('opening','transfer') LIMIT 1",
  );
  const id = String(row.id);
  const clearedAt = async () =>
    (await exec('SELECT p.cleared_at FROM postings p WHERE p.entry_id = ? AND p.account_id IS NOT NULL LIMIT 1', [id]))[0].cleared_at;
  expect(await clearedAt()).toBeNull();

  await applyMutation(exec, 'setCleared', { id, cleared: true });
  expect(await clearedAt()).not.toBeNull();

  await applyMutation(exec, 'setCleared', { id, cleared: false });
  expect(await clearedAt()).toBeNull();

  // Confirming a transaction does not clear it, and vice versa — independence
  // matters: the two flags answer different questions.
  await applyMutation(exec, 'setCleared', { id, cleared: true });
  const status = (await exec('SELECT status FROM entries WHERE id = ?', [id]))[0].status;
  expect(status).toBe('confirmed'); // unaffected by setCleared
});

test('setReviewed toggles reviewed_at; markAllReviewed clears the ledger queue', async () => {
  const exec = await seededAndAudited();
  // §2: reviewed_at on entries; look up entry id via account posting.
  const [row] = await exec(
    "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.status = 'confirmed' AND e.kind NOT IN ('opening','transfer') LIMIT 1",
  );
  const id = String(row.id);
  // Seed rows start unreviewed.
  expect((await exec('SELECT reviewed_at FROM entries WHERE id = ?', [id]))[0].reviewed_at).toBeNull();

  await applyMutation(exec, 'setReviewed', { id, reviewed: true });
  expect((await exec('SELECT reviewed_at FROM entries WHERE id = ?', [id]))[0].reviewed_at).not.toBeNull();

  await applyMutation(exec, 'setReviewed', { id, reviewed: false });
  expect((await exec('SELECT reviewed_at FROM entries WHERE id = ?', [id]))[0].reviewed_at).toBeNull();

  // markAllReviewed clears every unreviewed confirmed personal row.
  const before = Number(
    (await exec("SELECT COUNT(*) AS n FROM entries WHERE ledger_id = 'personal' AND status = 'confirmed' AND reviewed_at IS NULL AND kind NOT IN ('opening')") )[0].n,
  );
  expect(before).toBeGreaterThan(0);
  await applyMutation(exec, 'markAllReviewed', { ledgerId: 'personal' });
  const after = Number(
    (await exec("SELECT COUNT(*) AS n FROM entries WHERE ledger_id = 'personal' AND status = 'confirmed' AND reviewed_at IS NULL AND kind NOT IN ('opening')"))[0].n,
  );
  expect(after).toBe(0);
  // The family ledger is untouched (scope respected).
  const family = Number(
    (await exec("SELECT COUNT(*) AS n FROM entries WHERE ledger_id = 'family' AND reviewed_at IS NOT NULL"))[0].n,
  );
  expect(family).toBe(0);
});

test('deleteTransaction collects rel_paths via cascade and unlinks the files', async () => {
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const os = await import('node:os');

  const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'finch-mut-cascade-'));
  const prevDbDir = process.env.FINCH_DB_DIR;
  process.env.FINCH_DB_DIR = tmpRoot;
  try {
    const exec = await seededAndAudited();
    // §2: entry_attachments replaces transaction_attachments; use entry_id FK.
    const [tx] = await exec(
      "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind NOT IN ('opening','transfer') LIMIT 1",
    );
    const txId = String(tx.id);

    const paths = [
      `attachments/${txId}/a.jpg`,
      `attachments/${txId}/b.pdf`,
    ];
    for (const rel of paths) {
      const abs = path.join(tmpRoot, rel);
      await fs.mkdir(path.dirname(abs), { recursive: true });
      await fs.writeFile(abs, Buffer.from('x'));
    }
    await exec(
      `INSERT INTO entry_attachments
         (id, ledger_id, entry_id, kind, rel_path, mime_type, byte_size, sha256, original_filename, created_at, updated_at)
       VALUES ('att-a','personal',?,'image',?,'image/jpeg',1,'h',null,datetime('now'),datetime('now')),
              ('att-b','personal',?,'pdf',?,'application/pdf',1,'h',null,datetime('now'),datetime('now'))`,
      [txId, paths[0], txId, paths[1]],
    );

    await applyMutation(exec, 'deleteTransaction', { id: txId });

    // Both rows cascaded away (entries CASCADE deletes entry_attachments).
    expect((await exec('SELECT id FROM entry_attachments WHERE entry_id = ?', [txId])).length).toBe(0);
    // Both files unlinked.
    for (const rel of paths) {
      const abs = path.join(tmpRoot, rel);
      expect(await fs.access(abs).then(() => true, () => false)).toBe(false);
    }
  } finally {
    if (prevDbDir === undefined) delete process.env.FINCH_DB_DIR;
    else process.env.FINCH_DB_DIR = prevDbDir;
    await fs.rm(tmpRoot, { recursive: true, force: true }).catch(() => {});
  }
});

test('reconcileAccount stamps the checkpoint without an adjustment when none is asked', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'reconcileAccount', {
    accountId: 'chk',
    statementBalance: 9999.99,
    statementDate: '2026-05-31',
    postAdjustment: false,
  });
  const [row] = await exec(
    'SELECT last_reconciled_at AS d, last_reconciled_balance AS b FROM accounts WHERE id = ?',
    ['chk'],
  );
  expect(row.d).toBe('2026-05-31');
  expect(Number(row.b)).toBeCloseTo(9999.99, 2);
  // No adjustment row was inserted as part of this reconcile.
  // §2: check entries for adjustment kind (with posting to chk).
  const adj = await exec(
    "SELECT COUNT(*) AS c FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind = 'adjustment'",
  );
  expect(Number(adj[0].c)).toBe(0);
});

test('reconcileAccount with postAdjustment posts the exact remainder + lands cleared sum on target', async () => {
  const exec = await seededAndAudited();
  // Clear a handful of rows so the cleared sum is non-trivial.
  // §2: use entry ids (not transaction ids).
  const ids = (
    await exec(
      "SELECT e.id FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind NOT IN ('opening','transfer') LIMIT 3",
    )
  ).map((r) => String(r.id));
  for (const id of ids) await applyMutation(exec, 'setCleared', { id, cleared: true });

  // §2: opening_balance gone; cleared sum = SUM of cleared account postings.
  // §2: cleared_at is per-leg on postings (not on entries).
  const [sum] = await exec(
    `SELECT COALESCE(SUM(p.amount), 0) AS s
       FROM postings p JOIN entries e ON p.entry_id = e.id
     WHERE p.account_id = 'chk' AND e.status = 'confirmed' AND p.cleared_at IS NOT NULL`,
  );
  const clearedBefore = Math.round(Number(sum.s) * 100) / 100;
  const target = Math.round((clearedBefore + 12.5) * 100) / 100;

  await applyMutation(exec, 'reconcileAccount', {
    accountId: 'chk',
    statementBalance: target,
    statementDate: '2026-05-31',
    postAdjustment: true,
  });

  // The adjustment posted, was marked cleared, and lands the cleared sum exactly on target.
  // §2: adjustment is an entry with kind='adjustment'; amount on the account posting.
  // §2: cleared_at is per-leg on postings; check p.cleared_at.
  const [adj] = await exec(
    `SELECT p.amount, p.cleared_at FROM entries e JOIN postings p ON p.entry_id = e.id
      WHERE p.account_id = 'chk' AND e.kind = 'adjustment'
      ORDER BY e.created_at DESC LIMIT 1`,
  );
  expect(Number(adj.amount)).toBeCloseTo(12.5, 2);
  expect(adj.cleared_at).not.toBeNull();

  // §2: cleared_at is per-leg on postings.
  const [sumAfter] = await exec(
    `SELECT COALESCE(SUM(p.amount), 0) AS s
       FROM postings p JOIN entries e ON p.entry_id = e.id
     WHERE p.account_id = 'chk' AND e.status = 'confirmed' AND p.cleared_at IS NOT NULL`,
  );
  const clearedAfter = Math.round(Number(sumAfter.s) * 100) / 100;
  expect(clearedAfter).toBeCloseTo(target, 2);

  // Checkpoint stamped.
  const [acct] = await exec(
    'SELECT last_reconciled_at AS d, last_reconciled_balance AS b FROM accounts WHERE id = ?',
    ['chk'],
  );
  expect(acct.d).toBe('2026-05-31');
  expect(Number(acct.b)).toBeCloseTo(target, 2);
});

test('reconcileAccount with postAdjustment is a no-op on the adjustment when the gap is within the penny tolerance', async () => {
  const exec = await seededAndAudited();
  // §2: opening_balance column is gone. The cleared sum = SUM of pre-cleared opening
  // entry's account posting. Reconcile to that exact value → gap = 0 → no adjustment.
  const [sum] = await exec(
    `SELECT COALESCE(SUM(p.amount), 0) AS s
       FROM postings p JOIN entries e ON e.id = p.entry_id
      WHERE p.account_id = 'chk' AND e.status = 'confirmed' AND p.cleared_at IS NOT NULL`,
  );
  const clearedSum = Math.round(Number(sum.s) * 100) / 100;
  await applyMutation(exec, 'reconcileAccount', {
    accountId: 'chk',
    statementBalance: clearedSum,
    statementDate: '2026-05-31',
    postAdjustment: true,
  });
  // §2: check entries + postings for adjustment kind.
  const adj = await exec(
    "SELECT COUNT(*) AS c FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind = 'adjustment'",
  );
  expect(Number(adj[0].c)).toBe(0); // gap = 0 → within penny tolerance, no adjustment posted.
});

test('adjustAccountBalance posts a marked delta and moves balance to the target', async () => {
  const exec = await seededAndAudited();
  const before = await balanceOf(exec, 'chk'); // 4218.50 seed
  await applyMutation(exec, 'adjustAccountBalance', { accountId: 'chk', targetBalance: 5000, note: 'reconcile' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(5000, 2);
  // §2: entries + postings replace transactions. kind on entry, amount_base/description/notes on entry.
  const [adj] = await exec(
    "SELECT e.kind, p.amount_base, e.description, e.notes FROM entries e JOIN postings p ON p.entry_id = e.id WHERE p.account_id = 'chk' AND e.kind = 'adjustment' ORDER BY e.created_at DESC LIMIT 1",
  );
  expect(String(adj.kind)).toBe('adjustment');
  expect(Number(adj.amount_base)).toBeCloseTo(5000 - before, 2);
  expect(String(adj.description)).toBe('Balance adjustment');
  expect(String(adj.notes)).toBe('reconcile');
});

test('income via addTransaction (positive amount) increases the account balance', async () => {
  const exec = await seededAndAudited();
  const before = await balanceOf(exec, 'chk');
  await applyMutation(exec, 'addTransaction', {
    ledgerId: 'personal', accountId: 'chk', amount: 250, merchant: 'Side gig',
    categoryId: null, date: '2026-05-29', status: 'confirmed',
  });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(before + 250, 2);
});

test('duplicate guard: identical addTransaction is rejected with a friendly message', async () => {
  const exec = await seededAndAudited();
  const draft = {
    ledgerId: 'personal', accountId: 'chk', amount: -12.5, currency: 'USD',
    merchant: 'Double Latte', categoryId: 'food', date: '2026-05-20', time: '09:00',
    status: 'confirmed' as const,
  };
  await applyMutation(exec, 'addTransaction', draft);
  // Same account/date/time/amount/description → hits the dedup unique index on entries/postings.
  await expect(applyMutation(exec, 'addTransaction', draft)).rejects.toThrow(/duplicate/i);
  // A different time is a distinct row — allowed.
  await applyMutation(exec, 'addTransaction', { ...draft, time: '09:01' });
  // §2: description on entries.
  const n = await exec(
    "SELECT COUNT(*) AS c FROM entries WHERE description='Double Latte'",
  );
  expect(Number(n[0].c)).toBe(2);
});
