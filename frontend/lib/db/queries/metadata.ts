// Reads and writes for the single-row db_metadata table. The row is the source
// of truth for "what is this file?" — see schema.ts for the column shape.

import type { Exec } from '../core/repo';
import type { DbMetadata, ExportStamp } from '@/lib/db/domain/_app/metadata.types';

/** Read the single metadata row; returns null when the table is absent or empty. */
export async function readMetadata(exec: Exec): Promise<DbMetadata | null> {
  try {
    const rows = await exec('SELECT * FROM db_metadata WHERE id = 1');
    if (rows.length === 0) return null;
    const r = rows[0];
    return {
      appName: String(r.app_name),
      schemaVersion: String(r.schema_version),
      appVersion: String(r.app_version),
      createdAt: String(r.created_at),
      updatedAt: String(r.updated_at),
      exportedAt: r.exported_at == null ? null : String(r.exported_at),
      exportedFrom: r.exported_from == null ? null : String(r.exported_from),
      rowCounts: r.row_counts == null ? null : (JSON.parse(String(r.row_counts)) as Record<string, number>),
      checksum: r.checksum == null ? null : String(r.checksum),
    };
  } catch {
    // Table might not exist yet on a freshly-opened DB before applySchema runs.
    return null;
  }
}

/** Bump the metadata row's updated_at to "now" (in UTC ISO 8601). */
export async function bumpUpdated(exec: Exec): Promise<void> {
  await exec("UPDATE db_metadata SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = 1");
}

/** Stamp the metadata row with export-time provenance. Used by /api/export
 *  on a DB clone (not the live DB) so the live row never carries stale stamps. */
export async function stampExport(exec: Exec, stamp: ExportStamp): Promise<void> {
  await exec(
    `UPDATE db_metadata
       SET exported_at = ?, exported_from = ?, row_counts = ?, checksum = ?
     WHERE id = 1`,
    [stamp.exportedAt, stamp.exportedFrom, JSON.stringify(stamp.rowCounts), stamp.checksum],
  );
}

/** Canonical list of tables included in row_counts + checksum coverage. */
export const CANONICAL_TABLES = [
  'ledgers',
  'account_groups',
  'accounts',
  'categories',
  'counterparties',
  'entries',
  'postings',
  'entry_tags',
  'entry_attachments',
  'budgets',
  'tags',
  'scheduled_templates',
  'scheduled_splits',
  'exchange_rates',
  'app_state',
];

/** Row count per canonical table. Missing tables count as 0 (older files). */
export async function rowCounts(exec: Exec): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  for (const t of CANONICAL_TABLES) {
    try {
      const rows = await exec(`SELECT COUNT(*) AS n FROM ${t}`);
      out[t] = Number(rows[0]?.n ?? 0);
    } catch {
      out[t] = 0;
    }
  }
  return out;
}
