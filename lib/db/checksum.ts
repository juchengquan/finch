// SHA-256 over a deterministic row dump of the canonical tables. Stamped on
// export, verified on import; a mismatch is a hard reject (corruption /
// tampering). The dump excludes `db_metadata` itself — otherwise the checksum
// would depend on its own value.

import { createHash } from 'node:crypto';
import type { Exec } from '@/lib/db/repo';
import { CANONICAL_TABLES } from './queries/metadata';

/**
 * Deterministically dump every canonical table to a single string and hash it.
 * Rows are sorted by `id` when the table has one, otherwise by a stringified
 * key composed of every column (still deterministic, just slower).
 */
export async function computeChecksum(exec: Exec): Promise<string> {
  const hash = createHash('sha256');
  for (const table of CANONICAL_TABLES) {
    let rows: Record<string, unknown>[];
    try {
      // PRAGMA table_info tells us whether the table exists + its column shape.
      const info = await exec(`PRAGMA table_info(${table})`);
      if (info.length === 0) {
        hash.update(`${table}\n[]\n`);
        continue;
      }
      const hasId = info.some((c) => String(c.name) === 'id');
      const orderBy = hasId ? 'id' : info.map((c) => String(c.name)).join(', ');
      rows = await exec(`SELECT * FROM ${table} ORDER BY ${orderBy}`);
    } catch {
      hash.update(`${table}\n[]\n`);
      continue;
    }
    hash.update(`${table}\n`);
    for (const r of rows) {
      // Sort keys so column-order changes don't affect the hash; nulls / numbers
      // / strings all stringify deterministically via JSON.
      const stable = Object.keys(r)
        .sort()
        .reduce<Record<string, unknown>>((acc, k) => {
          acc[k] = r[k];
          return acc;
        }, {});
      hash.update(JSON.stringify(stable));
      hash.update('\n');
    }
  }
  return hash.digest('hex');
}
