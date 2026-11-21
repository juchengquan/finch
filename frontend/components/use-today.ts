'use client';

import { useSyncExternalStore } from 'react';
import { localToday } from '@/lib/local-today';

// Re-check once a minute, so a page left open past midnight moves to the new day.
const subscribe = (onChange: () => void) => {
  const id = setInterval(onChange, 60_000);
  return () => clearInterval(id);
};

/** The user's local date (YYYY-MM-DD), or null while rendering on the server and
 *  during hydration — the server's clock and time zone aren't the user's, and
 *  reading the clock there would make the two renders disagree. Callers fall back
 *  to something deterministic for that first paint. */
export function useToday(): string | null {
  return useSyncExternalStore(subscribe, localToday, () => null);
}
