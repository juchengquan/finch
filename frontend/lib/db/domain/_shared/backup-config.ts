// lib/db/domain/_shared/backup-config.ts — read-modify-write for the
// backupConfig app_state key (frequencyMs + retention).
import { getAppState, setAppState } from '../_app/appState';
import type { Exec } from '../../core/repo';

/** Merge a partial backup-config update into the app_state slice. Reads the
 *  existing JSON, overrides the named keys, writes back. Concurrent
 *  setBackupFrequency / setBackupRetention can't clobber each other this way.
 *  Defaults mirror `lib/db/state.ts::readBackupConfig`. */
export async function mergeBackupConfig(
  exec: Exec,
  patch: Partial<{ frequencyMs: number; retention: number }>,
): Promise<void> {
  const raw = await getAppState(exec, 'backupConfig');
  let cur: { frequencyMs: number; retention: number } = { frequencyMs: 60 * 60 * 1000, retention: 14 };
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        const f = Number((parsed as { frequencyMs?: unknown }).frequencyMs);
        const r = Number((parsed as { retention?: unknown }).retention);
        if (Number.isFinite(f)) cur.frequencyMs = Math.trunc(f);
        if (Number.isFinite(r) && r > 0) cur.retention = Math.trunc(r);
      }
    } catch {
      /* keep defaults */
    }
  }
  cur = { ...cur, ...patch };
  await setAppState(exec, 'backupConfig', JSON.stringify(cur));
}
