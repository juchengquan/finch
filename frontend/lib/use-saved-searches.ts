'use client';

import { useCallback, useSyncExternalStore } from 'react';

// Saved searches are a client-only convenience: pinned Activity filter sets,
// persisted to localStorage (NOT the server DB). They never travel with a DB
// export/backup and aren't mirrored through the Zustand store — they're a
// per-browser preference, like a bookmark.

export type SavedSearchDirection = 'all' | 'in' | 'out';

export interface SavedSearch {
  id: string;
  ledgerId: string;
  /** User label shown on the chip, e.g. "Subscriptions > $20". */
  name: string;
  /** Free-text merchant query (matches the Activity search box). */
  query: string;
  direction: SavedSearchDirection;
  /** Tag id to filter by, or null for "any tag". */
  tagId: string | null;
  /** Inclusive YYYY-MM-DD bounds; '' = unbounded. */
  fromDate: string;
  toDate: string;
  /** Absolute-amount bounds (magnitude); null = unbounded. */
  minAmount: number | null;
  maxAmount: number | null;
}

const STORAGE_KEY = 'finch.savedSearches';
const DIRECTIONS: ReadonlySet<string> = new Set(['all', 'in', 'out']);

/** Coerce one unknown value into a SavedSearch, or null if it's unusable —
 *  so a hand-edited / legacy localStorage value can't crash the page. */
function parseOne(v: unknown): SavedSearch | null {
  if (!v || typeof v !== 'object') return null;
  const o = v as Record<string, unknown>;
  if (typeof o.id !== 'string' || typeof o.ledgerId !== 'string' || typeof o.name !== 'string') {
    return null;
  }
  const num = (x: unknown): number | null => (typeof x === 'number' && Number.isFinite(x) ? x : null);
  return {
    id: o.id,
    ledgerId: o.ledgerId,
    name: o.name,
    query: typeof o.query === 'string' ? o.query : '',
    direction: typeof o.direction === 'string' && DIRECTIONS.has(o.direction) ? (o.direction as SavedSearchDirection) : 'all',
    tagId: typeof o.tagId === 'string' ? o.tagId : null,
    fromDate: typeof o.fromDate === 'string' ? o.fromDate : '',
    toDate: typeof o.toDate === 'string' ? o.toDate : '',
    minAmount: num(o.minAmount),
    maxAmount: num(o.maxAmount),
  };
}

// A cached parsed snapshot so getSnapshot returns a referentially-stable value
// between writes — useSyncExternalStore re-renders if the snapshot identity
// changes, so we only rebuild it when the raw string actually changes.
let cachedRaw: string | null = null;
let cachedList: SavedSearch[] = [];

function readList(): SavedSearch[] {
  const raw = typeof window === 'undefined' ? null : window.localStorage.getItem(STORAGE_KEY);
  if (raw === cachedRaw) return cachedList;
  cachedRaw = raw;
  try {
    const parsed = raw ? JSON.parse(raw) : [];
    cachedList = Array.isArray(parsed) ? parsed.map(parseOne).filter((s): s is SavedSearch => s !== null) : [];
  } catch {
    cachedList = [];
  }
  return cachedList;
}

const EMPTY: SavedSearch[] = [];
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

function persist(list: SavedSearch[]): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(list));
  } catch {
    /* quota / disabled storage — saved searches are best-effort */
  }
  // Notify same-tab subscribers (the `storage` event only fires in *other* tabs).
  for (const cb of listeners) cb();
}

/**
 * localStorage-backed saved searches. SSR-safe via useSyncExternalStore (server
 * snapshot is always empty, so first client render matches markup, then the
 * store snapshot takes over). Mutations write through synchronously and notify.
 */
export function useSavedSearches() {
  const searches = useSyncExternalStore(subscribe, readList, () => EMPTY);

  const save = useCallback((input: Omit<SavedSearch, 'id'>): string => {
    const id = `ss-${Date.now().toString(36)}`;
    persist([...readList(), { ...input, id }]);
    return id;
  }, []);

  const remove = useCallback((id: string) => {
    persist(readList().filter((s) => s.id !== id));
  }, []);

  return { searches, save, remove };
}
