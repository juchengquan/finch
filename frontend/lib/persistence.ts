// Single source of truth for loading persisted app state on startup.
//
// Precedence per browser:
//   1. OPFS `finch.sqlite3` (the relational SQLite file) — authoritative.
//   2. A legacy flat-schema `finch.db` in OPFS — read once and migrated; the
//      next save writes the relational file, which then wins forever.
//   3. localStorage — fallback for browsers without OPFS (and older data).
//   4. null — caller keeps the seed data.
//
// Saving lives in components/sqlite-backup-provider.tsx, which writes the same
// backend (OPFS when available, otherwise localStorage). We never keep two
// fresh copies, so there is no "which copy wins" ambiguity on reload.

import type { PersistState } from '@/lib/db/repo';

const LS_KEY = 'finch-store';

function withDefaults(s: Partial<PersistState>): PersistState {
  return {
    transactions: s.transactions ?? [],
    pending: s.pending ?? [],
    recurring: s.recurring ?? [],
    budgetOverrides: s.budgetOverrides ?? {},
    accountOverrides: s.accountOverrides ?? {},
    verifiedExtra: s.verifiedExtra ?? [],
    aliasExtra: s.aliasExtra ?? {},
  };
}

/** Read persisted state from localStorage, tolerating the legacy zustand wrapper. */
export function lsRead(): PersistState | null {
  if (typeof localStorage === 'undefined') return null;
  const raw = localStorage.getItem(LS_KEY);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    // zustand's persist middleware wrote `{ state, version }`; newer writes are
    // the bare PersistState. Accept either.
    const state = parsed?.state ?? parsed;
    if (!state || !Array.isArray(state.transactions)) return null;
    return withDefaults(state);
  } catch {
    return null;
  }
}

/** Write persisted state to localStorage (used only when OPFS is unavailable). */
export function lsWrite(state: PersistState): void {
  if (typeof localStorage === 'undefined') return;
  try {
    localStorage.setItem(LS_KEY, JSON.stringify(state));
  } catch {
    // Quota or privacy-mode errors are non-fatal — the in-memory store still works.
  }
}

/**
 * Load the persisted state for this device, or null to keep the seed data.
 * OPFS wins when available; otherwise localStorage.
 */
export async function loadPersisted(): Promise<PersistState | null> {
  if (typeof window === 'undefined') return null;

  const { opfsSupported, readOpfs, LEGACY_DB } = await import('@/lib/db/storage');

  if (opfsSupported()) {
    try {
      const bytes = await readOpfs();
      if (bytes) {
        const { deserializeState } = await import('@/lib/db/state');
        return await deserializeState(bytes);
      }
    } catch (err) {
      console.error('Could not read finch.sqlite3 from OPFS; falling back', err);
    }
    // No relational file yet — migrate once from a legacy flat finch.db, else
    // from localStorage. The next save writes the relational file for good.
    try {
      const legacy = await readOpfs(LEGACY_DB);
      if (legacy) {
        const { importBytesToState } = await import('@/lib/db/sqlite');
        return await importBytesToState(legacy);
      }
    } catch (err) {
      console.error('Could not read legacy finch.db; falling back', err);
    }
    return lsRead();
  }

  return lsRead();
}
