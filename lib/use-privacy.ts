'use client';

import { useCallback, useSyncExternalStore } from 'react';

// Privacy mode is a client-only, per-device preference (like saved searches
// and the locale): when on, every money formatter renders a mask instead of
// the figure, so the app can be shown on a train without broadcasting
// balances. Persisted to localStorage — never the DB, never exports.

/** What every masked amount renders as. */
export const MONEY_MASK = '••••';

const STORAGE_KEY = 'finch.privacy';

/** '1' is on; anything else (missing, legacy junk) is off. */
export function parsePrivacyRaw(raw: string | null): boolean {
  return raw === '1';
}

function read(): boolean {
  return parsePrivacyRaw(typeof window === 'undefined' ? null : window.localStorage.getItem(STORAGE_KEY));
}

const listeners = new Set<() => void>();

function subscribe(cb: () => void): () => void {
  listeners.add(cb);
  // Cross-tab: another tab writing the same key fires a `storage` event here.
  const onStorage = (e: StorageEvent) => {
    if (e.key === STORAGE_KEY) cb();
  };
  window.addEventListener('storage', onStorage);
  return () => {
    listeners.delete(cb);
    window.removeEventListener('storage', onStorage);
  };
}

function persist(on: boolean): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, on ? '1' : '0');
  } catch {
    /* quota / disabled storage — privacy mode is best-effort */
  }
  // Notify same-tab subscribers (the `storage` event only fires in *other* tabs).
  for (const cb of listeners) cb();
}

/**
 * localStorage-backed privacy toggle. SSR-safe via useSyncExternalStore (the
 * server snapshot is always off, so the hydration render matches the SSR
 * markup; the client snapshot takes over immediately after).
 */
export function usePrivacy() {
  const privacy = useSyncExternalStore(subscribe, read, () => false);
  const setPrivacy = useCallback((on: boolean) => persist(on), []);
  const toggle = useCallback(() => persist(!read()), []);
  return { privacy, setPrivacy, toggle };
}
