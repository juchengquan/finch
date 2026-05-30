'use client';

import { useSyncExternalStore } from 'react';

// The pool of consumer-app sections that can occupy the mobile bottom bar.
// Order here is also the desktop sidebar order. The pinned center "Add" button
// is not part of this catalog — it always sits in the middle of the bar.
export interface MainTab {
  id: string;
  icon: string;
  label: string;
  path: string;
}

export const MAIN_TAB_CATALOG: MainTab[] = [
  { id: 'accounts', icon: 'wallet', label: 'Accounts', path: '/accounts' },
  { id: 'budgets', icon: 'target', label: 'Budgets', path: '/budgets' },
  { id: 'scheduled', icon: 'calendar', label: 'Scheduled', path: '/scheduled' },
  { id: 'insights', icon: 'chart', label: 'Insights', path: '/insights' },
  { id: 'goals', icon: 'sparkle', label: 'Goals', path: '/goals' },
  { id: 'subscriptions', icon: 'sync', label: 'Subscriptions', path: '/subscriptions' },
  { id: 'reports', icon: 'doc', label: 'Reports', path: '/reports' },
  { id: 'activity', icon: 'clock', label: 'Activity', path: '/activity' },
];

// How many sections flank the center Add button (4 → a 5-slot bar).
export const MOBILE_TAB_SLOTS = 4;

export const DEFAULT_MOBILE_TAB_IDS = ['accounts', 'budgets', 'scheduled', 'insights'];

const STORAGE_KEY = 'finch.mobileTabs';

const tabById = (id: string) => MAIN_TAB_CATALOG.find((t) => t.id === id);

// Drop unknown/duplicate ids and cap at MOBILE_TAB_SLOTS so a stale or hand-
// edited localStorage value can never break the bar.
function sanitize(ids: unknown): string[] | null {
  if (!Array.isArray(ids)) return null;
  const seen = new Set<string>();
  const clean = ids.filter(
    (id): id is string => typeof id === 'string' && !!tabById(id) && !seen.has(id) && (seen.add(id), true),
  );
  return clean.length ? clean.slice(0, MOBILE_TAB_SLOTS) : null;
}

// Module-level external store backed by localStorage. Read via
// useSyncExternalStore so SSR and the hydration render both use the default
// (getServerSnapshot) while the client adopts the persisted value on the next
// render — no hydration mismatch, no setState-in-effect.
let snapshot: string[] = DEFAULT_MOBILE_TAB_IDS;
if (typeof window !== 'undefined') {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    const next = raw ? sanitize(JSON.parse(raw)) : null;
    if (next) snapshot = next;
  } catch {
    /* ignore malformed storage */
  }
}

const listeners = new Set<() => void>();
const subscribe = (cb: () => void) => {
  listeners.add(cb);
  return () => listeners.delete(cb);
};
const getSnapshot = () => snapshot;
const getServerSnapshot = () => DEFAULT_MOBILE_TAB_IDS;

function setTabIds(ids: string[]) {
  snapshot = sanitize(ids) ?? DEFAULT_MOBILE_TAB_IDS;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot));
  } catch {
    /* ignore quota/availability errors */
  }
  listeners.forEach((l) => l());
}

interface MobileTabs {
  /** Selected section ids, in bar order (left → right, excluding Add). */
  tabIds: string[];
  setTabIds: (ids: string[]) => void;
  /** Selected sections resolved to catalog entries. */
  tabs: MainTab[];
  catalog: MainTab[];
}

export function useMobileTabs(): MobileTabs {
  const tabIds = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
  const tabs = tabIds.map(tabById).filter((t): t is MainTab => !!t);
  return { tabIds, setTabIds, tabs, catalog: MAIN_TAB_CATALOG };
}
