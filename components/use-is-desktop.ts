'use client';

import { useSyncExternalStore } from 'react';

// Matches Tailwind's `md` breakpoint (the app's mobile/desktop split).
const QUERY = '(min-width: 768px)';

function subscribe(callback: () => void) {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return () => {};
  const mql = window.matchMedia(QUERY);
  // Safari < 14 (and some old WebViews) only have the deprecated addListener.
  // Calling the missing addEventListener there throws and, because this hook
  // runs in a top-level provider, can break the whole app's hydration.
  if (typeof mql.addEventListener === 'function') {
    mql.addEventListener('change', callback);
    return () => mql.removeEventListener('change', callback);
  }
  mql.addListener(callback);
  return () => mql.removeListener(callback);
}

function getSnapshot() {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return false;
  return window.matchMedia(QUERY).matches;
}

// Server (and the hydration render) assumes mobile, then corrects after mount.
// Anything gated on this is closed at first paint, so there's no visible flash.
function getServerSnapshot() {
  return false;
}

/** True on viewports ≥ 768px. SSR-safe (no hydration mismatch). */
export function useIsDesktop(): boolean {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}
