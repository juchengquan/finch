'use client';

import { createContext, useContext, useEffect, useRef, useState } from 'react';
import { useFinanceStore } from '@/lib/store';
import type { Exec, PersistState } from '@/lib/db/repo';
import type { LiveDb } from '@/lib/db/client';

// The live query DB exposed to components. `exec` runs SQL; `version` bumps each
// time the DB is rebuilt from the store so query hooks can re-run.
interface DbContextValue {
  exec: Exec | null;
  version: number;
}

const DbContext = createContext<DbContextValue>({ exec: null, version: 0 });

export function useDb(): DbContextValue {
  return useContext(DbContext);
}

function snapshot(): PersistState {
  const s = useFinanceStore.getState();
  return {
    transactions: s.transactions,
    pending: s.pending,
    budgetOverrides: s.budgetOverrides,
    accountOverrides: s.accountOverrides,
    verifiedExtra: s.verifiedExtra,
    aliasExtra: s.aliasExtra,
    recurring: s.recurring,
  };
}

const DEBOUNCE_MS = 150;

export function DbProvider({ children }: { children: React.ReactNode }) {
  const [ctx, setCtx] = useState<DbContextValue>({ exec: null, version: 0 });
  const dbRef = useRef<LiveDb | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const running = useRef(false);
  const queued = useRef(false);

  useEffect(() => {
    let disposed = false;

    const rebuild = async () => {
      if (running.current) {
        queued.current = true;
        return;
      }
      running.current = true;
      try {
        do {
          queued.current = false;
          const { buildLiveDb } = await import('@/lib/db/runtime');
          const live = await buildLiveDb(snapshot());
          if (disposed) {
            live.close();
            return;
          }
          dbRef.current?.close();
          dbRef.current = live;
          setCtx((c) => ({ exec: live.exec, version: c.version + 1 }));
        } while (queued.current);
      } catch (err) {
        console.error('Could not build the query DB', err);
      } finally {
        running.current = false;
      }
    };

    const schedule = () => {
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => void rebuild(), DEBOUNCE_MS);
    };

    // Build once on mount, then rebuild whenever the store changes.
    void rebuild();
    const unsub = useFinanceStore.subscribe(schedule);
    return () => {
      disposed = true;
      unsub();
      if (timer.current) clearTimeout(timer.current);
      dbRef.current?.close();
      dbRef.current = null;
    };
  }, []);

  return <DbContext.Provider value={ctx}>{children}</DbContext.Provider>;
}
