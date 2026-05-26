'use client';

import { createContext, useContext, useState, type ReactNode } from 'react';
import ledgersData from '@/data/ledgers.json';

export interface Ledger {
  id: string;
  name: string;
  base: string;
  isDefault: number;
  accounts: number;
  txns: number;
  color: string;
  tagline: string;
}

export const LEDGERS = ledgersData as Ledger[];

interface LedgerContextValue {
  ledgers: Ledger[];
  activeId: string;
  active: Ledger;
  setActiveId: (id: string) => void;
}

const LedgerContext = createContext<LedgerContextValue | null>(null);

export function LedgerProvider({ children }: { children: ReactNode }) {
  const [activeId, setActiveId] = useState(
    LEDGERS.find((l) => l.isDefault)?.id ?? LEDGERS[0].id,
  );
  const active = LEDGERS.find((l) => l.id === activeId) ?? LEDGERS[0];

  return (
    <LedgerContext.Provider value={{ ledgers: LEDGERS, activeId, active, setActiveId }}>
      {children}
    </LedgerContext.Provider>
  );
}

export function useLedger() {
  const ctx = useContext(LedgerContext);
  if (!ctx) throw new Error('useLedger must be used within LedgerProvider');
  return ctx;
}
