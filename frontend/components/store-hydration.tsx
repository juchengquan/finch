'use client';

import { useEffect } from 'react';
import { useFinanceStore } from '@/lib/store';
import { loadPersisted } from '@/lib/persistence';

// The store starts from seed data so server and first-client render match.
// After mount we load the persisted state — the SQLite `finch.db` in OPFS when
// available, otherwise localStorage — and replace the seed with it.
export function StoreHydration() {
  useEffect(() => {
    let cancelled = false;
    void loadPersisted().then((state) => {
      if (state && !cancelled) useFinanceStore.setState(state);
    });
    return () => {
      cancelled = true;
    };
  }, []);
  return null;
}
