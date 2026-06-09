// lib/db/domain/_shared/mobile-tabs.ts — read-modify-write helpers for the
// mobileTabs and displayCurrencyByLedger app_state keys.
import { getAppState, setAppState } from '../_app/appState';
import type { Exec } from '../../core/repo';

export async function setMobileTabIds(exec: Exec, ids: string[]): Promise<void> {
  await setAppState(exec, 'mobileTabs', JSON.stringify(ids));
}

// Merge the single ledger's choice into the stored map so a concurrent
// edit to a different ledger isn't clobbered.
export async function setDisplayCurrency(
  exec: Exec,
  ledgerId: string,
  currency: string,
): Promise<void> {
  const raw = await getAppState(exec, 'displayCurrencyByLedger');
  let map: Record<string, string> = {};
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) map = parsed as Record<string, string>;
    } catch {
      /* ignore malformed value */
    }
  }
  map[ledgerId] = currency;
  await setAppState(exec, 'displayCurrencyByLedger', JSON.stringify(map));
}
