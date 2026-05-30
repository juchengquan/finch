'use client';

import { useEffect } from 'react';
import { useFinanceStore } from '@/lib/store';
import { fetchState, mutate } from '@/lib/api-client';

// Today as a local 'YYYY-MM-DD' so "due" matches the user's calendar day.
function localToday(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

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

    // First load: materialize any due scheduled occurrences (idempotent), which
    // returns the full projected state. Fall back to a plain read on failure.
    inFlight = true;
    void mutate('generateDueScheduled', { today: localToday() })
      .then((state) => {
        if (!cancelled) useFinanceStore.setState(state);
      })
      .catch((err) => {
        console.error('Could not generate scheduled items', err);
        if (!cancelled) sync();
      })
      .finally(() => {
        inFlight = false;
      });

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
