import { expect, test } from 'bun:test';
import { bareDb } from './test-utils';
import { IN_CHUNK, selectInChunks } from './in-chunks';
import type { Exec } from './repo';

test('selectInChunks returns every row while no statement carries more than a chunk of parameters', async () => {
  const { exec } = await bareDb();
  await exec('CREATE TABLE t (id TEXT PRIMARY KEY, n INTEGER)');
  const ids = Array.from({ length: 12_345 }, (_, i) => `id-${i}`);
  for (let i = 0; i < ids.length; i += 500) {
    const part = ids.slice(i, i + 500);
    await exec(`INSERT INTO t (id, n) VALUES ${part.map(() => '(?, 1)').join(',')}`, part);
  }
  let most = 0;
  const counting: Exec = (sql, params = []) => {
    most = Math.max(most, params.length);
    return exec(sql, params);
  };
  const rows = await selectInChunks(counting, ids, (ph) => `SELECT id FROM t WHERE id IN (${ph})`, 1000);
  expect(rows.length).toBe(ids.length);
  expect(most).toBe(1000);
  // The default stays well under better-sqlite3's 32,766-parameter cap.
  expect(IN_CHUNK).toBeLessThan(32_766);
});
