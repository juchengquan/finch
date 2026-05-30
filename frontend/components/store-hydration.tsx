'use client';

import { useEffect } from 'react';
import { useFinanceStore } from '@/lib/store';
import { fetchState } from '@/lib/api-client';

// The store starts from seed data so server and first-client render match.
// After mount we load the authoritative state from the server database and
// replace the seed with it. Mutations sync back to the server (see store.ts).
//
// Each tab keeps its own in-memory mirror, so a change made in one tab is
// invisible to others until they re-sync. We therefore also refetch whenever
// the tab regains visibility/focus — switching back to a tab pulls the latest
// server state (which already includes every committed mutation).
export function StoreHydration() {
  useEffect(() => {
    let cancelled = false;
    let inFlight = false;

    const sync = () => {
      if (inFlight) return;
      inFlight = true;
      void fetchState()
        .then((state) => {
          if (!cancelled) useFinanceStore.setState(state);
        })
        .catch((err) => console.error('Could not load state from server', err))
        .finally(() => {
          inFlight = false;
        });
    };

    sync();

    const onVisible = () => {
      if (document.visibilityState === 'visible') sync();
    };
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('focus', sync);

    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('focus', sync);
    };
  }, []);
  return null;
}
