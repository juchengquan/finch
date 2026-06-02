'use client';

import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';
import ledgersData from '@/data/ledgers.json';
import { useFinanceStore } from '@/lib/store';

export interface Ledger {
  id: string;
  name: string;
  /** Active base currency. Sourced from the projected DB row at runtime;
   *  the static JSON only kicks in before the store hydrates. */
  base: string;
  isDefault: number;
  accounts: number;
  txns: number;
  color: string;
  tagline: string;
}

interface StaticLedger {
  id: string;
  name: string;
  base: string;
  isDefault: number;
  accounts: number;
  txns: number;
  color: string;
  tagline: string;
}

const STATIC = ledgersData as StaticLedger[];

interface LedgerContextValue {
  ledgers: Ledger[];
  activeId: string;
  active: Ledger;
  setActiveId: (id: string) => void;
}

const LedgerContext = createContext<LedgerContextValue | null>(null);

export function LedgerProvider({ children }: { children: ReactNode }) {
  const projected = useFinanceStore((s) => s.ledgers);
  const [activeId, setActiveId] = useState(
    STATIC.find((l) => l.isDefault)?.id ?? STATIC[0].id,
  );

  // Merge: live DB rows for name/base/isDefault; static JSON for cosmetic
  // fields (color/tagline/accounts/txns). Falls back to pure static before
  // the store hydrates so first paint isn't empty.
  const ledgers = useMemo<Ledger[]>(() => {
    if (!projected.length) return STATIC;
    const staticById = new Map(STATIC.map((s) => [s.id, s]));
    return projected.map((p) => {
      const cosmetic = staticById.get(p.id);
      return {
        id: p.id,
        name: p.name,
        base: p.base,
        isDefault: p.isDefault,
        accounts: cosmetic?.accounts ?? 0,
        txns: cosmetic?.txns ?? 0,
        color: cosmetic?.color ?? '#888',
        tagline: cosmetic?.tagline ?? '',
      };
    });
  }, [projected]);

  const active = ledgers.find((l) => l.id === activeId) ?? ledgers[0];

  return (
    <LedgerContext.Provider value={{ ledgers, activeId, active, setActiveId }}>
      {children}
    </LedgerContext.Provider>
  );
}

export function useLedger() {
  const ctx = useContext(LedgerContext);
  if (!ctx) throw new Error('useLedger must be used within LedgerProvider');
  return ctx;
}

/** Static fallback list used only before the store hydrates (e.g. SSR or
 *  the first render of pages that read ledgers via `LEDGERS` directly). */
export const LEDGERS = STATIC;
