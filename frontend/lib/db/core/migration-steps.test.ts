import { expect, test } from 'bun:test';
import { freshDb } from './test-utils';
import { migrate } from './schema';

const versionOf = async (exec: Awaited<ReturnType<typeof freshDb>>['exec']) =>
  String((await exec('SELECT schema_version FROM db_metadata WHERE id = 1'))[0].schema_version);

test('a migration that fails half-way is rolled back, and the file stays at the last complete version', async () => {
  const { exec } = await freshDb();
  await migrate(exec, { fresh: true }); // writes the metadata row
  await exec("UPDATE db_metadata SET schema_version = '2000-01-01T00:00:00Z' WHERE id = 1");
  const err = await migrate(exec, { fresh: false }, {
    '2000-01-02T00:00:00Z': ['CREATE TABLE step_one (id TEXT)'],
    '2000-01-03T00:00:00Z': ['CREATE TABLE step_two (id TEXT NOT NULL)', 'INSERT INTO step_two (id) VALUES (NULL)'],
  }).then(() => null, (e) => e);
  expect(err).toBeTruthy();
  const tables = (await exec("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'step_%'")).map((r) => String(r.name));
  // Step one landed and is recorded; step two's first statement was rolled back with it.
  expect(tables).toEqual(['step_one']);
  expect(await versionOf(exec)).toBe('2000-01-02T00:00:00Z');
});

test('a table rebuild runs with foreign keys off, so dropping the old table cascades nothing', async () => {
  const { exec } = await freshDb();
  await migrate(exec, { fresh: true }); // writes the metadata row
  await exec("UPDATE db_metadata SET schema_version = '2000-01-01T00:00:00Z' WHERE id = 1");
  await exec('CREATE TABLE parent_t (id TEXT PRIMARY KEY)');
  await exec('CREATE TABLE child_t (id TEXT, parent_id TEXT REFERENCES parent_t(id) ON DELETE CASCADE)');
  await exec("INSERT INTO parent_t VALUES ('p1')");
  await exec("INSERT INTO child_t VALUES ('c1', 'p1')");
  await migrate(exec, { fresh: false }, {
    '2000-01-02T00:00:00Z': [
      'PRAGMA foreign_keys = OFF',
      'CREATE TABLE parent_t_new (id TEXT PRIMARY KEY, note TEXT)',
      'INSERT INTO parent_t_new (id) SELECT id FROM parent_t',
      'DROP TABLE parent_t',
      'ALTER TABLE parent_t_new RENAME TO parent_t',
      'PRAGMA foreign_keys = ON',
    ],
  });
  expect((await exec('SELECT id FROM child_t')).length).toBe(1);
  expect(Number((await exec('PRAGMA foreign_keys'))[0].foreign_keys)).toBe(1);
});
