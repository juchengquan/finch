'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from 'react';
import { toast } from 'sonner';
import { useFinanceStore } from '@/lib/store';
import type { PersistState } from '@/lib/db/repo';

type SyncStatus = 'idle' | 'saving' | 'error';

interface BackupContextValue {
  opfs: boolean;
  fsAccess: boolean;
  connected: boolean;
  fileName: string | null;
  lastSync: number | null;
  status: SyncStatus;
  connectBackup: () => Promise<void>;
  disconnectBackup: () => void;
  download: () => Promise<void>;
  importFile: (file: Blob) => Promise<void>;
}

const noop = async () => {};
const BackupContext = createContext<BackupContextValue>({
  opfs: false,
  fsAccess: false,
  connected: false,
  fileName: null,
  lastSync: null,
  status: 'idle',
  connectBackup: noop,
  disconnectBackup: () => {},
  download: noop,
  importFile: noop,
});

export function useBackup(): BackupContextValue {
  return useContext(BackupContext);
}

// The slice of store state we persist (mirrors the store's partialize).
function snapshot(): PersistState {
  const s = useFinanceStore.getState();
  return {
    transactions: s.transactions,
    pending: s.pending,
    budgetOverrides: s.budgetOverrides,
    verifiedExtra: s.verifiedExtra,
    aliasExtra: s.aliasExtra,
    recurring: s.recurring,
  };
}

// Capability detection via useSyncExternalStore so the server snapshot (false)
// matches the first client render, then re-renders to the real value — no
// effect/setState and no hydration mismatch.
const subscribeNoop = () => () => {};
const getServerFalse = () => false;
const getOpfs = () =>
  typeof navigator !== 'undefined' &&
  !!navigator.storage &&
  typeof navigator.storage.getDirectory === 'function';
const getFsAccess = () =>
  typeof window !== 'undefined' && typeof window.showSaveFilePicker === 'function';

const DEBOUNCE_MS = 800;

export function SqliteBackupProvider({ children }: { children: React.ReactNode }) {
  const opfs = useSyncExternalStore(subscribeNoop, getOpfs, getServerFalse);
  const fsAccess = useSyncExternalStore(subscribeNoop, getFsAccess, getServerFalse);

  const [connected, setConnected] = useState(false);
  const [fileName, setFileName] = useState<string | null>(null);
  const [lastSync, setLastSync] = useState<number | null>(null);
  const [status, setStatus] = useState<SyncStatus>('idle');

  const handleRef = useRef<FileSystemFileHandle | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const running = useRef(false);
  const queued = useRef(false);

  // Serialise the current store snapshot to a `.db` and write it to every
  // available sink. Coalesces concurrent calls so writes never overlap: a call
  // arriving mid-flush sets `queued`, and the loop runs one more pass.
  const flushNow = useCallback(async () => {
    if (running.current) {
      queued.current = true;
      return;
    }
    running.current = true;
    try {
      do {
        queued.current = false;
        setStatus('saving');
        try {
          const [{ exportStateToBytes }, storage] = await Promise.all([
            import('@/lib/db/sqlite'),
            import('@/lib/db/storage'),
          ]);
          const bytes = await exportStateToBytes(snapshot());
          if (storage.opfsSupported()) await storage.writeOpfs(bytes);
          if (handleRef.current) await storage.writeHandle(handleRef.current, bytes);
          setLastSync(Date.now());
          setStatus('idle');
        } catch (err) {
          console.error('SQLite backup failed', err);
          setStatus('error');
        }
      } while (queued.current);
    } finally {
      running.current = false;
    }
  }, []);

  const schedule = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => void flushNow(), DEBOUNCE_MS);
  }, [flushNow]);

  // Auto-mirror on every store change (rehydrate-on-mount counts as a change,
  // so the first sync happens shortly after load).
  useEffect(() => {
    const unsub = useFinanceStore.subscribe(() => schedule());
    return () => {
      unsub();
      if (timer.current) clearTimeout(timer.current);
    };
  }, [schedule]);

  const connectBackup = useCallback(async () => {
    const storage = await import('@/lib/db/storage');
    if (!storage.fsAccessSupported()) {
      toast.error('This browser cannot save to a local file');
      return;
    }
    try {
      const handle = await storage.pickBackupFile();
      handleRef.current = handle;
      setFileName(handle.name);
      setConnected(true);
      await flushNow();
      toast.success(`Backup file connected: ${handle.name}`);
    } catch (err) {
      // The picker throws AbortError when the user cancels — that's not an error.
      if ((err as DOMException)?.name !== 'AbortError') {
        console.error(err);
        toast.error('Could not connect backup file');
      }
    }
  }, [flushNow]);

  const disconnectBackup = useCallback(() => {
    handleRef.current = null;
    setConnected(false);
    setFileName(null);
  }, []);

  const download = useCallback(async () => {
    const [{ exportStateToBytes }, storage] = await Promise.all([
      import('@/lib/db/sqlite'),
      import('@/lib/db/storage'),
    ]);
    const bytes = await exportStateToBytes(snapshot());
    storage.downloadBytes(bytes);
  }, []);

  const importFile = useCallback(
    async (file: Blob) => {
      const [{ importBytesToState }, storage] = await Promise.all([
        import('@/lib/db/sqlite'),
        import('@/lib/db/storage'),
      ]);
      const bytes = await storage.readFileBytes(file);
      const state = await importBytesToState(bytes);
      useFinanceStore.setState(state);
      await flushNow();
      toast.success('Database imported');
    },
    [flushNow],
  );

  return (
    <BackupContext.Provider
      value={{
        opfs,
        fsAccess,
        connected,
        fileName,
        lastSync,
        status,
        connectBackup,
        disconnectBackup,
        download,
        importFile,
      }}
    >
      {children}
    </BackupContext.Provider>
  );
}
