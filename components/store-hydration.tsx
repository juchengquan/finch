'use client';

import { useEffect, useRef } from 'react';
import { useTranslations } from 'next-intl';
import { toast } from 'sonner';
import { useFinanceStore } from '@/lib/store';
import { SYNC_FAILED_EVENT, type SyncFailedDetail } from '@/lib/store/hydrate';
import { fetchState, mutate } from '@/lib/api-client';
import type { ErrorWithI18n } from '@/lib/i18n-error';

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
  const t = useTranslations();
  // Read through a ref so the effect below runs once, not on every locale change.
  const tRef = useRef(t);
  useEffect(() => {
    tRef.current = t;
  }, [t]);

  useEffect(() => {
    let cancelled = false;
    let inFlight = false;

    const sync = (force = false) => {
      if (inFlight && !force) return;
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
    const onFocus = () => sync();

    // A rejected mutation leaves the optimistic local change on screen as if
    // it had saved. Reload the server's state (it never took the change) and
    // say so. `force`: a read already in flight may have left before the
    // failure, but its answer is still the server's truth — fetching again
    // costs one request and can't show anything stale.
    const onSyncFailed = (e: Event) => {
      const { error } = (e as CustomEvent<SyncFailedDetail>).detail;
      const tr = tRef.current;
      const coded = error as Partial<ErrorWithI18n> | undefined;
      const reason =
        coded?.code && tr.has(coded.code)
          ? tr(coded.code, coded.params)
          : error instanceof Error
            ? error.message
            : undefined;
      toast.error(tr('error.syncFailed'), { description: reason });
      if (!cancelled) sync(true);
    };

    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('focus', onFocus);
    window.addEventListener(SYNC_FAILED_EVENT, onSyncFailed);

    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('focus', onFocus);
      window.removeEventListener(SYNC_FAILED_EVENT, onSyncFailed);
    };
  }, []);
  return null;
}
