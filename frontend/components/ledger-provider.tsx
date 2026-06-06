'use client';

import { createContext, useCallback, useContext, useMemo, useSyncExternalStore, type ReactNode } from 'react';
import ledgersData from '@/data/ledgers.json';
import { useFinanceStore } from '@/lib/store';

export interface Ledger {
  id: string;
  name: string;
  /** Active base currency. Sourced from the projected DB row at runtime;
   *  the static JSON only kicks in before the store hydrates. */
  base: string;
  isDefault: number;
  accounts: number;
  txns: number;
  /** Always a string for the UI's convenience — defaults to a derived hue
   *  when the projected row's `color` is null. */
  color: string;
  /** Always a string — empty when the projected row has no tagline. */
  tagline: string;
}

interface StaticLedger {
  id: string;
  name: string;
  base: string;
  isDefault: number;
  accounts: number;
  txns: number;
  color: string;
  tagline: string;
}

const STATIC = ledgersData as StaticLedger[];

interface LedgerContextValue {
  ledgers: Ledger[];
  activeId: string;
  active: Ledger;
  setActiveId: (id: string) => void;
}

const LedgerContext = createContext<LedgerContextValue | null>(null);

// Per-device active-ledger preference (LEDGER_CRUD_PLAN §6). Persisted to
// localStorage with this key so it survives reloads on the same browser; the
// choice is a device/session preference (your phone on Family shouldn't flip
// the desktop off Personal). A one-line swap to an `app_state` key would
// flip this to ledger-data if cross-device sync ever becomes the call.
const ACTIVE_LEDGER_KEY = 'finch.activeLedger';

function readPersistedActiveId(): string | null {
  if (typeof window === 'undefined') return null;
  try {
    return window.localStorage.getItem(ACTIVE_LEDGER_KEY);
  } catch {
    return null;
  }
}

function writePersistedActiveId(id: string): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(ACTIVE_LEDGER_KEY, id);
  } catch {
    /* localStorage unavailable / quota — fall back to no-op */
  }
  // Same-tab updates: the `storage` event only fires across tabs, dispatch
  // manually so our useSyncExternalStore subscribers re-read in this tab.
  window.dispatchEvent(new StorageEvent('storage', { key: ACTIVE_LEDGER_KEY }));
}

function subscribeActiveId(cb: () => void): () => void {
  if (typeof window === 'undefined') return () => undefined;
  const onStorage = (e: StorageEvent) => {
    if (e.key === ACTIVE_LEDGER_KEY) cb();
  };
  window.addEventListener('storage', onStorage);
  return () => window.removeEventListener('storage', onStorage);
}

// Cheap deterministic hue from the id when the projected row has no color.
// Hash the id to one of the chart-1..5 tokens so the fallback matches the
// app palette.
const FALLBACK_HUES = ['#c96442', '#5e7d5e', '#c89a3e', '#6b8ab0', '#8a6ba8'];
function colorForId(id: string): string {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) & 0xffffffff;
  return FALLBACK_HUES[Math.abs(h) % FALLBACK_HUES.length];
}

export function LedgerProvider({ children }: { children: ReactNode }) {
  const projected = useFinanceStore((s) => s.ledgers);

  // Live DB rows take over once the store hydrates. STATIC is only the
  // pre-hydration shape. Fallbacks: null color -> hashed hue from id; null
  // tagline -> empty string.
  const ledgers = useMemo<Ledger[]>(() => {
    if (!projected.length) return STATIC;
    return projected.map((p) => ({
      id: p.id,
      name: p.name,
      base: p.base,
      isDefault: p.isDefault,
      accounts: p.accounts,
      txns: p.txns,
      color: p.color ?? colorForId(p.id),
      tagline: p.tagline ?? '',
    }));
  }, [projected]);

  // useSyncExternalStore: SSR-safe read from localStorage with cross-tab
  // updates via the storage event. Server snapshot is null so the first
  // client render matches.
  const persisted = useSyncExternalStore(
    subscribeActiveId,
    readPersistedActiveId,
    () => null,
  );

  // Derive the effective active id during render — no setState-in-effect
  // cascade. Use the persisted value when it points to a known ledger,
  // otherwise fall back to the default (or first available).
  const activeId =
    persisted && ledgers.some((l) => l.id === persisted)
      ? persisted
      : (ledgers.find((l) => l.isDefault === 1) ?? ledgers[0])?.id ?? '';

  const setActiveId = useCallback((id: string) => {
    writePersistedActiveId(id);
  }, []);

  const active = ledgers.find((l) => l.id === activeId) ?? ledgers[0];

  return (
    <LedgerContext.Provider value={{ ledgers, activeId, active, setActiveId }}>
      {children}
    </LedgerContext.Provider>
  );
}

export function useLedger() {
  const ctx = useContext(LedgerContext);
  if (!ctx) throw new Error('useLedger must be used within LedgerProvider');
  return ctx;
}

/** Static fallback list used only before the store hydrates (e.g. SSR or
 *  the first render of pages that read ledgers via `LEDGERS` directly). */
export const LEDGERS = STATIC;
