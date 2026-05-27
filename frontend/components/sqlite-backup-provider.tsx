'use client';

import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { useFinanceStore } from '@/lib/store';
import { fetchDbInfo } from '@/lib/api-client';
import type { PersistState } from '@/lib/db/repo';

// The server owns the authoritative SQLite file (see lib/db/server.ts), synced
// on every change. This provider just surfaces where that file lives and lets
// the user download a point-in-time copy of the current data.
interface BackupContextValue {
  serverPath: string | null;
  download: () => Promise<void>;
}

const BackupContext = createContext<BackupContextValue>({
  serverPath: null,
  download: async () => {},
});

export function useBackup(): BackupContextValue {
  return useContext(BackupContext);
}

function snapshot(): PersistState {
  const s = useFinanceStore.getState();
  return {
    transactions: s.transactions,
    budgetOverrides: s.budgetOverrides,
    accountOverrides: s.accountOverrides,
    verifiedExtra: s.verifiedExtra,
    aliasExtra: s.aliasExtra,
    recurring: s.recurring,
  };
}

export function SqliteBackupProvider({ children }: { children: React.ReactNode }) {
  const [serverPath, setServerPath] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void fetchDbInfo()
      .then((info) => {
        if (!cancelled) setServerPath(info.path);
      })
      .catch((err) => console.error('Could not read db info', err));
    return () => {
      cancelled = true;
    };
  }, []);

  const download = useCallback(async () => {
    const [{ serializeState }, storage] = await Promise.all([
      import('@/lib/db/state'),
      import('@/lib/db/storage'),
    ]);
    const bytes = await serializeState(snapshot());
    storage.downloadBytes(bytes);
  }, []);

  return <BackupContext.Provider value={{ serverPath, download }}>{children}</BackupContext.Provider>;
}
