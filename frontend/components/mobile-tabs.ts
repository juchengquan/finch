'use client';

import { useTranslations } from 'next-intl';
import { useFinanceStore } from '@/lib/store';

// The pool of consumer-app sections that can occupy the mobile bottom bar.
// Order here is also the desktop sidebar order. The pinned center "Add" button
// is not part of this catalog — it always sits in the middle of the bar.
//
// The hardcoded `label` slot is kept (defaulted to the English string) for the
// rare callsite that reads the catalog outside React (e.g. tests). React
// callers use `useMobileTabs` / `useMainTabCatalog` to get localised labels.
export interface MainTab {
  id: string;
  icon: string;
  label: string;
  path: string;
}

interface MainTabSeed {
  id: string;
  icon: string;
  path: string;
}

const MAIN_TAB_SEEDS: MainTabSeed[] = [
  { id: 'accounts', icon: 'wallet', path: '/accounts' },
  { id: 'budgets', icon: 'target', path: '/budgets' },
  { id: 'scheduled', icon: 'calendar', path: '/scheduled' },
  { id: 'insights', icon: 'chart', path: '/insights' },
  { id: 'activity', icon: 'clock', path: '/activity' },
];

export const MAIN_TAB_CATALOG: MainTab[] = MAIN_TAB_SEEDS.map((s) => ({
  ...s,
  // English fallback. React consumers override via the hooks below.
  label: s.id[0].toUpperCase() + s.id.slice(1),
}));

/** Localised version of `MAIN_TAB_CATALOG`. Sidebar/bottom-bar consumers call
 *  this so labels reflect the active UI language. */
export function useMainTabCatalog(): MainTab[] {
  const tNav = useTranslations('nav');
  return MAIN_TAB_SEEDS.map((s) => ({ ...s, label: tNav(s.id) }));
}

// How many sections flank the center Add button (4 → a 5-slot bar).
export const MOBILE_TAB_SLOTS = 4;

export const DEFAULT_MOBILE_TAB_IDS = ['accounts', 'budgets', 'scheduled', 'insights'];

const tabById = (id: string, catalog: MainTab[]) => catalog.find((t) => t.id === id);

// Drop unknown/duplicate ids and cap at MOBILE_TAB_SLOTS so a stale or
// hand-edited stored value can never break the bar. Returns null when nothing
// usable remains, so the caller can fall back to the default.
function sanitize(ids: unknown, catalog: MainTab[]): string[] | null {
  if (!Array.isArray(ids)) return null;
  const seen = new Set<string>();
  const clean = ids.filter(
    (id): id is string => typeof id === 'string' && !!tabById(id, catalog) && !seen.has(id) && (seen.add(id), true),
  );
  return clean.length ? clean.slice(0, MOBILE_TAB_SLOTS) : null;
}

interface MobileTabs {
  /** Selected section ids, in bar order (left → right, excluding Add). */
  tabIds: string[];
  setTabIds: (ids: string[]) => void;
  /** Selected sections resolved to catalog entries. */
  tabs: MainTab[];
  catalog: MainTab[];
}

// The selection lives in the synced finance store (persisted to the DB), so it
// follows the user across devices. Until the store hydrates — or when the stored
// value is empty/invalid — we fall back to the default set.
export function useMobileTabs(): MobileTabs {
  const stored = useFinanceStore((s) => s.mobileTabIds);
  const setTabIds = useFinanceStore((s) => s.setMobileTabIds);
  const catalog = useMainTabCatalog();
  const tabIds = sanitize(stored, catalog) ?? DEFAULT_MOBILE_TAB_IDS;
  const tabs = tabIds.map((id) => tabById(id, catalog)).filter((t): t is MainTab => !!t);
  return { tabIds, setTabIds, tabs, catalog };
}
