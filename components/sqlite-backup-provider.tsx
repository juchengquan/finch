'use client';

import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { fetchDbInfo } from '@/lib/api-client';

const base = process.env.NODE_ENV === 'development' ? '' : (process.env.NEXT_PUBLIC_BASE_PATH || '/finch');

// The server owns the authoritative SQLite file (see lib/db/server.ts), synced
// on every change. This provider surfaces where that file lives and downloads a
// point-in-time copy by streaming the live server file (so table edits — renamed
// accounts, budgets, etc. — are included).
interface BackupContextValue {
  serverPath: string | null;
  download: () => Promise<void>;
  downloadCsv: () => Promise<void>;
}

const BackupContext = createContext<BackupContextValue>({
  serverPath: null,
  download: async () => {},
  downloadCsv: async () => {},
});

export function useBackup(): BackupContextValue {
  return useContext(BackupContext);
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
    const res = await fetch(`${base}/api/export`);
    if (!res.ok) throw new Error(`Export failed (${res.status})`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    const { downloadBytes } = await import('@/lib/db/storage');
    downloadBytes(bytes);
  }, []);

  const downloadCsv = useCallback(async () => {
    const res = await fetch(`${base}/api/export/transactions`);
    if (!res.ok) throw new Error(`CSV export failed (${res.status})`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    const { downloadBytes } = await import('@/lib/db/storage');
    downloadBytes(bytes, 'finch-transactions.csv', 'text/csv;charset=utf-8');
  }, []);

  return <BackupContext.Provider value={{ serverPath, download, downloadCsv }}>{children}</BackupContext.Provider>;
}
