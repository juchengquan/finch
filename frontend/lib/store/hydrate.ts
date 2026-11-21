// frontend/lib/store/hydrate.ts — the server-bridge helper. Moved from
// lib/store.ts:375-400. The store's per-domain action creators call
// syncMutation(action, args) after their optimistic local update; the
// server's POST /api/mutate returns a fresh ProjectedState which
// wholesale-replaces the store via useFinanceStore.setState(state).
//
// This module is the SOLE entry point for the client → server mutation
// round-trip. It depends on `@/lib/api-client` (dynamic import to
// avoid SSR window access) and on the store's `useFinanceStore`.

import { useFinanceStore } from './index';

/** Fired on `window` when the server rejects a mutation. The optimistic
 *  local change is then wrong: StoreHydration listens, reloads the server's
 *  state (dropping that change) and tells the user. */
export const SYNC_FAILED_EVENT = 'finch:sync-failed';

export interface SyncFailedDetail {
  action: string;
  error: unknown;
}

export function syncMutation(action: string, args?: Record<string, unknown>): void {
  if (typeof window === 'undefined') return;
  void import('@/lib/api-client')
    .then(({ mutate }) => mutate(action, args))
    .then((state) => {
      useFinanceStore.setState(state);
    })
    .catch((err) => {
      console.error(`Sync failed (${action})`, err);
      window.dispatchEvent(
        new CustomEvent<SyncFailedDetail>(SYNC_FAILED_EVENT, { detail: { action, error: err } }),
      );
    });
}
