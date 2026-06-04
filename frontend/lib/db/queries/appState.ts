import type { Exec } from '../repo';

// Generic accessors for the transitional `app_state` key/value table: a home for
// single app-level preferences that don't yet warrant their own table. Values are
// opaque strings (JSON-encode structured data at the call site).

export async function getAppState(exec: Exec, key: string): Promise<string | null> {
  const rows = await exec('SELECT value FROM app_state WHERE key = ?', [key]);
  return rows[0]?.value == null ? null : String(rows[0].value);
}

export async function setAppState(exec: Exec, key: string, value: string): Promise<void> {
  await exec(
    `INSERT INTO app_state (key, value, created_at, updated_at)
     VALUES (?, ?, datetime('now'), datetime('now'))
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')`,
    [key, value],
  );
}
