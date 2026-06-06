import { test, expect } from 'bun:test';
import {
  listAttachments,
  getAttachmentFile,
  getAttachmentRelPathsForTransaction,
  getAttachmentRelPathsForLedger,
  countAttachmentsForTransaction,
  insertAttachment,
  deleteAttachment,
} from '@/lib/db/queries/attachments';
import { freshDb as freshTestDb } from '@/lib/db/test-utils';
import type { Exec } from '@/lib/db/repo';

/** Seeded ledger + account + one transaction the attachments can FK to. */
async function freshDb(): Promise<Exec> {
  const { exec } = await freshTestDb();
  await exec(
    `INSERT INTO ledgers (id, name, base_currency, created_at, updated_at)
     VALUES ('personal','Personal','USD',datetime('now'),datetime('now')),
            ('family',  'Family',  'SGD',datetime('now'),datetime('now'))`,
  );
  await exec(
    `INSERT INTO accounts (id, ledger_id, name, type, currency, opening_balance, opening_balance_base, created_at, updated_at)
     VALUES ('chk', 'personal', 'Checking', 'savings', 'USD', 0, 0, datetime('now'), datetime('now'))`,
  );
  await exec(
    `INSERT INTO transactions (id, ledger_id, account_id, date, amount, amount_base, exchange_rate, currency, created_at, updated_at)
     VALUES ('t1','personal','chk','2026-05-15',-10,-10,1,'USD',datetime('now'),datetime('now')),
            ('t2','personal','chk','2026-05-16',-20,-20,1,'USD',datetime('now'),datetime('now'))`,
  );
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
  await exec(
    `INSERT INTO accounts (id, ledger_id, name, type, currency, opening_balance, opening_balance_base, created_at, updated_at)
     VALUES ('fam-chk','family','Family Checking','savings','SGD',0,0,datetime('now'),datetime('now'))`,
  );
  await exec(
    `INSERT INTO transactions (id, ledger_id, account_id, date, amount, amount_base, exchange_rate, currency, created_at, updated_at)
     VALUES ('t-fam','family','fam-chk','2026-05-15',-30,-30,1,'SGD',datetime('now'),datetime('now'))`,
  );
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

test('FK cascade on transaction delete removes the attachment rows', async () => {
  const exec = await freshDb();
  await insertAttachment(exec, sample);
  await insertAttachment(exec, { ...sample, id: 'att-2', relPath: 'attachments/t1/att-2.pdf', kind: 'pdf', mimeType: 'application/pdf' });
  expect(await countAttachmentsForTransaction(exec, 't1')).toBe(2);

  await exec('DELETE FROM transactions WHERE id = ?', ['t1']);
  expect(await countAttachmentsForTransaction(exec, 't1')).toBe(0);
  expect(await getAttachmentFile(exec, 'att-1')).toBeNull();
});

test('FK cascade on ledger delete removes the attachment rows', async () => {
  const exec = await freshDb();
  await insertAttachment(exec, sample);
  expect((await listAttachments(exec, 'personal')).length).toBe(1);

  // Ledger delete cascades through accounts → transactions → attachments.
  await exec('DELETE FROM ledgers WHERE id = ?', ['personal']);
  expect((await listAttachments(exec, 'personal')).length).toBe(0);
});

test('CHECK constraint rejects an unknown kind', async () => {
  const exec = await freshDb();
  let threw = false;
  try {
    await exec(
      `INSERT INTO transaction_attachments
         (id, ledger_id, transaction_id, kind, rel_path, mime_type, byte_size, sha256, original_filename, created_at, updated_at)
       VALUES ('bad', 'personal', 't1', 'video', 'x', 'video/mp4', 1, 'h', null, datetime('now'), datetime('now'))`,
    );
  } catch {
    threw = true;
  }
  expect(threw).toBe(true);
});
