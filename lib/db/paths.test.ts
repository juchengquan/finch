import { test, expect, beforeAll, afterAll } from 'bun:test';
import path from 'node:path';
import { dbDir, attachmentsDir, resolveAttachmentPath } from '@/lib/db/paths';

let originalDbDir: string | undefined;

beforeAll(() => {
  originalDbDir = process.env.FINCH_DB_DIR;
  process.env.FINCH_DB_DIR = '/tmp/finch-paths-test';
});

afterAll(() => {
  if (originalDbDir === undefined) delete process.env.FINCH_DB_DIR;
  else process.env.FINCH_DB_DIR = originalDbDir;
});

test('dbDir reads FINCH_DB_DIR', () => {
  expect(dbDir()).toBe('/tmp/finch-paths-test');
});

test('attachmentsDir joins under dbDir', () => {
  expect(attachmentsDir()).toBe('/tmp/finch-paths-test/attachments');
});

test('resolveAttachmentPath: well-formed rel_path resolves under the root', () => {
  const abs = resolveAttachmentPath('attachments/tx-1/att-1.jpg');
  expect(abs).toBe('/tmp/finch-paths-test/attachments/tx-1/att-1.jpg');
});

test('resolveAttachmentPath: path-traversal attempt is refused', () => {
  // The classic ".." escape from inside `attachments/`.
  expect(resolveAttachmentPath('attachments/../finch.sqlite3')).toBeNull();
  // Multiple levels up.
  expect(resolveAttachmentPath('attachments/../../etc/passwd')).toBeNull();
});

test('resolveAttachmentPath: absolute paths that fall outside the root are refused', () => {
  expect(resolveAttachmentPath('/etc/passwd')).toBeNull();
});

test('resolveAttachmentPath: a normalised path under the root resolves', () => {
  expect(resolveAttachmentPath('attachments/./tx-1/att-1.jpg'))
    .toBe('/tmp/finch-paths-test/attachments/tx-1/att-1.jpg');
});

test('resolveAttachmentPath: handles platform path separator', () => {
  // path.sep is '/' on linux/macOS — sanity check the helper builds the
  // boundary correctly so resolved == root doesn't match by prefix.
  expect(path.sep).toBe('/');
  expect(resolveAttachmentPath('attachments-not-this')).toBeNull();
});
