// lib/db/domain/_app/metadata.types.ts — public row shapes for the metadata
// utility (db_metadata + export stamps). Keep this file free of SQL imports
// — it should be safe to import from any layer (UI components, route
// handlers, app_state) without pulling in the DB driver.

export interface DbMetadata {
  appName: string;
  schemaVersion: string;
  appVersion: string;
  createdAt: string;
  updatedAt: string;
  exportedAt: string | null;
  exportedFrom: string | null;
  rowCounts: Record<string, number> | null;
  checksum: string | null;
}

export interface ExportStamp {
  exportedAt: string;
  exportedFrom: string | null;
  rowCounts: Record<string, number>;
  checksum: string;
}
