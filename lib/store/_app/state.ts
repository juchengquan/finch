// frontend/lib/store/_app/state.ts — cross-cutting "app" slice of the
// initial state. Pure data; the action creators (added in Task 4) live
// in _app/actions.ts. The slice is small: per-device prefs (mobileTabIds),
// per-ledger display currency, and the auto-backup config.

export const appInitial = {
  mobileTabIds: [] as string[],
  displayCurrencyByLedger: {} as Record<string, string>,
  backupConfig: { frequencyMs: 60 * 60 * 1000, retention: 14 },
} as const;
