// frontend/lib/store/_app/actions.ts — app-level (cross-cutting) action
// creators. Extracted from lib/store.ts:360-389 (setMobileTabIds,
// setDisplayCurrency, setBackupFrequency, setBackupRetention,
// changeLedgerBase) + lib/store.ts:1154-1160 (reset).
//
// These are not domain-bound actions — they touch the cross-cutting
// `mobileTabIds` / `displayCurrencyByLedger` / `backupConfig` slices
// plus the ledgers slice (for `changeLedgerBase` and `reset`).
// `reset` also re-seeds the transactions / scheduled slices from the
// initial seed JSON.

import transactionsData from '@/data/transactions.json';
import scheduledData from '@/data/scheduled-templates.json';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';
import type { Tx, ScheduledTemplate } from '@/lib/store';

const SEED_TX = transactionsData as Tx[];
const SEED_SCHEDULED = scheduledData as ScheduledTemplate[];

export const appActions = (set: SetState, get: GetState) => ({
  setMobileTabIds: (ids: string[]) => {
    set({ mobileTabIds: ids });
    syncMutation('setMobileTabIds', { ids });
  },

  setDisplayCurrency: (ledgerId: string, currency: string) => {
    set((s) => ({ displayCurrencyByLedger: { ...s.displayCurrencyByLedger, [ledgerId]: currency } }));
    syncMutation('setDisplayCurrency', { ledgerId, currency });
  },

  setBackupFrequency: (frequencyMs: number) => {
    set((s) => ({ backupConfig: { ...s.backupConfig, frequencyMs } }));
    syncMutation('setBackupFrequency', { frequencyMs });
  },

  setBackupRetention: (retention: number) => {
    set((s) => ({ backupConfig: { ...s.backupConfig, retention } }));
    syncMutation('setBackupRetention', { retention });
  },

  changeLedgerBase: (ledgerId: string, newBase: string) => {
    // The server-side recompute rewrites every locked amount_base in the
    // ledger; the projection that comes back has the new base and the
    // re-derived figures everywhere. Optimistic update flips the local
    // base immediately so the UI doesn't show stale labels.
    set((s) => ({
      ledgers: s.ledgers.map((l) => (l.id === ledgerId ? { ...l, base: newBase } : l)),
    }));
    syncMutation('changeLedgerBase', { ledgerId, newBase });
  },

  reset: () => {
    set({
      transactions: SEED_TX,
      scheduled: SEED_SCHEDULED,
    });
    syncMutation('reset');
  },
});
