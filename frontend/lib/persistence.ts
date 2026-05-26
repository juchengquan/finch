// Single source of truth for loading persisted app state on startup.
//
// Precedence per browser:
//   1. OPFS `finch.db` (the real SQLite file) — authoritative when supported.
//   2. localStorage — fallback for browsers without OPFS, and a one-time
//      migration source for users whose data predates the SQLite store.
//   3. null — caller keeps the seed data.
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

  const { opfsSupported, readOpfs } = await import('@/lib/db/storage');

  if (opfsSupported()) {
    try {
      const bytes = await readOpfs();
      if (bytes) {
        const { importBytesToState } = await import('@/lib/db/sqlite');
        return await importBytesToState(bytes);
      }
    } catch (err) {
      console.error('Could not read finch.db from OPFS; falling back', err);
    }
    // OPFS exists but is empty (first run) or unreadable — migrate from any
    // legacy localStorage data. The next change writes it to OPFS for good.
    return lsRead();
  }

  return lsRead();
}
