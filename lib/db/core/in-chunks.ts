import type { Exec, Row } from './repo';

// SQLite caps the number of `?` parameters in one statement. better-sqlite3
// (Node, so `next start`) allows 32,766; bun:sqlite allows more, which is why
// the tests never saw it. A ledger past ~32k transactions made every state load
// fail on one `entry_id IN (…)` query. Queries over an unbounded id list go
// through here, a chunk at a time. (FinchCore needs no such thing: Apple's
// SQLite allows 500,000.)
export const IN_CHUNK = 5000;

/** Run `sql(ph, n)` once per chunk of `ids` and concatenate the rows. `ph` is
 *  the chunk's placeholder list, `n` its length. The query must not depend on
 *  seeing every id at once (per-id GROUP BY is fine; a global ORDER BY across
 *  chunks is not preserved). */
export async function selectInChunks(
  exec: Exec,
  ids: readonly string[],
  sql: (ph: string, n: number) => string,
  chunk = IN_CHUNK,
): Promise<Row[]> {
  const out: Row[] = [];
  for (let i = 0; i < ids.length; i += chunk) {
    const part = ids.slice(i, i + chunk);
    out.push(...(await exec(sql(part.map(() => '?').join(','), part.length), part)));
  }
  return out;
}
