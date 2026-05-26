'use client';

import { useEffect } from 'react';
import { useFinanceStore } from '@/lib/store';

// The store uses persist({ skipHydration: true }) so server and first-client
// render match the seed; we rehydrate from localStorage after mount.
export function StoreHydration() {
  useEffect(() => {
    useFinanceStore.persist.rehydrate();
  }, []);
  return null;
}
