import { test, expect } from 'bun:test';
import {
  listAttachments,
  getAttachmentFile,
  getAttachmentRelPathsForTransaction,
  getAttachmentRelPathsForLedger,
  countAttachmentsForTransaction,
  insertAttachment,
  deleteAttachment,
  resolveAttachmentTarget,
} from '@/lib/db/queries/attachments';
import { freshDb as freshTestDb } from '../core/test-utils';
import type { Exec } from '../core/repo';

/** Seeded ledger + account + entries the attachments can FK to. */
async function freshDb(): Promise<Exec> {
  const { exec } = await freshTestDb();
  await exec(
    `INSERT INTO ledgers (id, name, base_currency, created_at, updated_at)
     VALUES ('personal','Personal','USD',datetime('now'),datetime('now')),
            ('family',  'Family',  'SGD',datetime('now'),datetime('now'))`,
  );
  await exec(
    `INSERT INTO account_groups (id, ledger_id, name, sort_order, created_at, updated_at)
     VALUES ('cash', 'personal', 'Cash', 0, datetime('now'), datetime('now')),
            ('cash-fam', 'family', 'Cash', 0, datetime('now'), datetime('now'))`,
  );
  await exec(
    `INSERT INTO accounts (id, ledger_id, group_id, name, type, currency, current_balance, color, include_in_net_worth, is_active, created_at, updated_at)
     VALUES ('chk', 'personal', 'cash', 'Checking', 'savings', 'USD', 0, null, 1, 1, datetime('now'), datetime('now'))`,
  );
  // Insert entries directly (sealed=0 so no balance check trigger fires on the headers).
  // We only need the entry rows to exist as FK targets for attachments.
  await exec(
    `INSERT INTO entries (id, ledger_id, date, kind, status, sealed, created_at, updated_at)
     VALUES ('t1','personal','2026-05-15','expense','confirmed',1,datetime('now'),datetime('now')),
            ('t2','personal','2026-05-16','expense','confirmed',1,datetime('now'),datetime('now'))`,
  );
  // Postings to satisfy the seal trigger (sum must ≈ 0, ≥ 2 rows, ≥ 1 account leg).
  // We set sealed=1 on insert, so we need to bypass the trigger.
  // Instead: pre-seal by using sealed=0 then updating — or just leave sealed=1 since
  // we inserted entries directly (no trigger fired on INSERT INTO entries).
  // The tr_post_sealed_insert fires on postings INSERT when entry.sealed=1, so we
  // must insert postings BEFORE sealing. Re-do: insert entries with sealed=0,
  // insert postings, then seal.
  await exec(`UPDATE entries SET sealed = 0 WHERE id IN ('t1','t2')`);
  await exec(
    `INSERT INTO postings (id, entry_id, account_id, category_id, amount, currency, amount_base, exchange_rate, sort_order)
     VALUES ('t1-acct','t1','chk',null,-10,'USD',-10,1,0),
            ('t1-cat', 't1',null,null,10,'USD',10,1,1),
            ('t2-acct','t2','chk',null,-20,'USD',-20,1,0),
            ('t2-cat', 't2',null,null,20,'USD',20,1,1)`,
  );
  await exec(`UPDATE entries SET sealed = 1 WHERE id IN ('t1','t2')`);
  return exec;
}

const sample = {
  id: 'att-1',
  ledgerId: 'personal',
  transactionId: 't1',
  kind: 'image' as const,
  relPath: 'attachments/t1/att-1.jpg',
  mimeType: 'image/jpeg',
  byteSize: 12345,
  sha256: 'a'.repeat(64),
  originalFilename: 'receipt.jpg',
};

test('insertAttachment + listAttachments: round-trips the projected fields, omits rel_path', async () => {
  const exec = await freshDb();
  await insertAttachment(exec, sample);

  const list = await listAttachments(exec, 'personal');
  expect(list).toHaveLength(1);
  const a = list[0];
  expect(a.id).toBe('att-1');
  expect(a.ledgerId).toBe('personal');
  expect(a.transactionId).toBe('t1');
  expect(a.kind).toBe('image');
  expect(a.mimeType).toBe('image/jpeg');
  expect(a.byteSize).toBe(12345);
  expect(a.sha256).toBe(sample.sha256);
  expect(a.originalFilename).toBe('receipt.jpg');
  expect(a.createdAt).toBeTruthy();
  // The projection MUST NOT carry rel_path — clients can't construct URLs.
  expect((a as unknown as { relPath?: string }).relPath).toBeUndefined();
});

test('listAttachments without a ledgerId returns all ledgers', async () => {
  const exec = await freshDb();
  // Insert a family account and entry.
  await exec(
    `INSERT INTO accounts (id, ledger_id, group_id, name, type, currency, current_balance, color, include_in_net_worth, is_active, created_at, updated_at)
     VALUES ('fam-chk','family','cash-fam','Family Checking','savings','SGD',0,null,1,1,datetime('now'),datetime('now'))`,
  );
  await exec(
    `INSERT INTO entries (id, ledger_id, date, kind, status, sealed, created_at, updated_at)
     VALUES ('t-fam','family','2026-05-15','expense','confirmed',0,datetime('now'),datetime('now'))`,
  );
  await exec(
    `INSERT INTO postings (id, entry_id, account_id, amount, currency, amount_base, exchange_rate, sort_order)
     VALUES ('t-fam-a','t-fam','fam-chk',-30,'SGD',-30,1,0),
            ('t-fam-c','t-fam',null,30,'SGD',30,1,1)`,
  );
  await exec(`UPDATE entries SET sealed = 1 WHERE id = 't-fam'`);

  await insertAttachment(exec, sample);
  await insertAttachment(exec, { ...sample, id: 'att-fam', ledgerId: 'family', transactionId: 't-fam', relPath: 'attachments/t-fam/att-fam.jpg' });

  expect((await listAttachments(exec, 'personal')).map((a) => a.id)).toEqual(['att-1']);
  expect((await listAttachments(exec, 'family')).map((a) => a.id)).toEqual(['att-fam']);
  expect((await listAttachments(exec)).map((a) => a.id).sort()).toEqual(['att-1', 'att-fam']);
});

test('getAttachmentFile returns rel_path; null on miss', async () => {
  const exec = await freshDb();
  await insertAttachment(exec, sample);

  const file = await getAttachmentFile(exec, 'att-1');
  expect(file).not.toBeNull();
  expect(file!.relPath).toBe('attachments/t1/att-1.jpg');
  expect(file!.id).toBe('att-1');

  const miss = await getAttachmentFile(exec, 'does-not-exist');
  expect(miss).toBeNull();
});

test('getAttachmentRelPathsForTransaction collects all paths on one tx', async () => {
  const exec = await freshDb();
  await insertAttachment(exec, sample);
  await insertAttachment(exec, { ...sample, id: 'att-2', relPath: 'attachments/t1/att-2.pdf', kind: 'pdf', mimeType: 'application/pdf' });
  await insertAttachment(exec, { ...sample, id: 'att-3', transactionId: 't2', relPath: 'attachments/t2/att-3.jpg' });

  const t1Paths = await getAttachmentRelPathsForTransaction(exec, 't1');
  expect(t1Paths.sort()).toEqual(['attachments/t1/att-1.jpg', 'attachments/t1/att-2.pdf']);

  expect(await getAttachmentRelPathsForTransaction(exec, 't2')).toEqual(['attachments/t2/att-3.jpg']);
  expect(await getAttachmentRelPathsForTransaction(exec, 'none')).toEqual([]);
});

test('getAttachmentRelPathsForLedger scopes by ledger', async () => {
  const exec = await freshDb();
  await insertAttachment(exec, sample);
  await insertAttachment(exec, { ...sample, id: 'att-2', transactionId: 't2', relPath: 'attachments/t2/att-2.jpg' });

  expect((await getAttachmentRelPathsForLedger(exec, 'personal')).sort()).toEqual([
    'attachments/t1/att-1.jpg',
    'attachments/t2/att-2.jpg',
  ]);
  expect(await getAttachmentRelPathsForLedger(exec, 'family')).toEqual([]);
});

test('countAttachmentsForTransaction', async () => {
  const exec = await freshDb();
  expect(await countAttachmentsForTransaction(exec, 't1')).toBe(0);
  await insertAttachment(exec, sample);
  await insertAttachment(exec, { ...sample, id: 'att-2', relPath: 'attachments/t1/att-2.pdf', kind: 'pdf', mimeType: 'application/pdf' });
  expect(await countAttachmentsForTransaction(exec, 't1')).toBe(2);
  expect(await countAttachmentsForTransaction(exec, 't2')).toBe(0);
});

test('deleteAttachment removes one row', async () => {
  const exec = await freshDb();
  await insertAttachment(exec, sample);
  expect(await getAttachmentFile(exec, 'att-1')).not.toBeNull();

  await deleteAttachment(exec, 'att-1');
  expect(await getAttachmentFile(exec, 'att-1')).toBeNull();
});

test('FK cascade on entry delete removes the attachment rows', async () => {
  const exec = await freshDb();
  await insertAttachment(exec, sample);
  await insertAttachment(exec, { ...sample, id: 'att-2', relPath: 'attachments/t1/att-2.pdf', kind: 'pdf', mimeType: 'application/pdf' });
  expect(await countAttachmentsForTransaction(exec, 't1')).toBe(2);

  // Unseal the entry so CASCADE works (sealed postings guard only blocks INSERT/UPDATE/DELETE on postings).
  // Actually the entry DELETE cascades to entry_attachments (FK ON DELETE CASCADE), not via postings.
  // But we need to unseal first to allow postings to be deleted by cascade.
  await exec(`UPDATE entries SET sealed = 0 WHERE id = 't1'`);
  await exec('DELETE FROM entries WHERE id = ?', ['t1']);
  expect(await countAttachmentsForTransaction(exec, 't1')).toBe(0);
  expect(await getAttachmentFile(exec, 'att-1')).toBeNull();
});

test('FK cascade on ledger delete removes the attachment rows', async () => {
  const exec = await freshDb();
  await insertAttachment(exec, sample);
  expect((await listAttachments(exec, 'personal')).length).toBe(1);

  // Ledger delete cascades through accounts → entries → attachments.
  // Must unseal entries first to allow cascade.
  await exec(`UPDATE entries SET sealed = 0 WHERE ledger_id = 'personal'`);
  await exec('DELETE FROM ledgers WHERE id = ?', ['personal']);
  expect((await listAttachments(exec, 'personal')).length).toBe(0);
});

test('resolveAttachmentTarget resolves account-posting id, entry id, and returns null for unknown', async () => {
  // The upload route uses this helper instead of the dropped `transactions` table.
  const exec = await freshDb();

  // t1-acct is the account-posting id for entry t1.
  const byPosting = await resolveAttachmentTarget(exec, 't1-acct');
  expect(byPosting).not.toBeNull();
  expect(byPosting!.entryId).toBe('t1');
  expect(byPosting!.ledgerId).toBe('personal');

  // Passing the entry id directly also works.
  const byEntry = await resolveAttachmentTarget(exec, 't1');
  expect(byEntry).not.toBeNull();
  expect(byEntry!.entryId).toBe('t1');
  expect(byEntry!.ledgerId).toBe('personal');

  // Unknown id returns null.
  const miss = await resolveAttachmentTarget(exec, 'nope');
  expect(miss).toBeNull();

  // Confirm insertAttachment against the resolved entryId lands the correct row.
  const target = byPosting!;
  await insertAttachment(exec, {
    ...sample,
    id: 'att-resolved',
    ledgerId: target.ledgerId,
    transactionId: target.entryId,
    relPath: `attachments/${target.entryId}/att-resolved.jpg`,
  });
  const row = await getAttachmentFile(exec, 'att-resolved');
  expect(row).not.toBeNull();
  expect(row!.transactionId).toBe('t1'); // entry_id stored on the row
});

test('CHECK constraint rejects an unknown kind', async () => {
  const exec = await freshDb();
  let threw = false;
  try {
    await exec(
      `INSERT INTO entry_attachments
         (id, ledger_id, entry_id, kind, rel_path, mime_type, byte_size, sha256, original_filename, created_at, updated_at)
       VALUES ('bad', 'personal', 't1', 'video', 'x', 'video/mp4', 1, 'h', null, datetime('now'), datetime('now'))`,
    );
  } catch {
    threw = true;
  }
  expect(threw).toBe(true);
});
