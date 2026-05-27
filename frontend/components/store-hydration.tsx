'use client';

import { useEffect } from 'react';
import { useFinanceStore } from '@/lib/store';
import { fetchState } from '@/lib/api-client';

// The store starts from seed data so server and first-client render match.
// After mount we load the authoritative state from the server database and
// replace the seed with it. Mutations sync back to the server (see store.ts).
export function StoreHydration() {
  useEffect(() => {
    let cancelled = false;
    void fetchState()
      .then((state) => {
        if (!cancelled) useFinanceStore.setState(state);
      })
      .catch((err) => console.error('Could not load state from server', err));
    return () => {
      cancelled = true;
    };
  }, []);
  return null;
}
