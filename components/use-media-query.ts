'use client';

import { useSyncExternalStore } from 'react';

/** Whether `query` matches, or null while rendering on the server and during
 *  hydration (there is no viewport there). Callers render both variants (with
 *  CSS deciding) until it is known, then only the one that applies. */
export function useMediaQuery(query: string): boolean | null {
  return useSyncExternalStore(
    (onChange) => {
      const mql = window.matchMedia(query);
      mql.addEventListener('change', onChange);
      return () => mql.removeEventListener('change', onChange);
    },
    () => window.matchMedia(query).matches,
    () => null,
  );
}
