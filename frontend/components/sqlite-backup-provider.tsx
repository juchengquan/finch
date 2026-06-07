'use client';

import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { fetchDbInfo } from '@/lib/api-client';
import type { AuditProblem } from '@/lib/db/entries';

const base = process.env.NODE_ENV === 'development' ? '' : (process.env.NEXT_PUBLIC_BASE_PATH || '/finch');

// The server owns the authoritative SQLite file (see lib/db/server.ts), synced
// on every change. This provider surfaces where that file lives, downloads a
// point-in-time copy, and drives import / on-disk-backup / restore operations
// from the Settings UI.

export interface DbMetadataView {
  appName: string;
  schemaVersion: string;
  appVersion: string;
  createdAt: string;
  updatedAt: string;
  exportedAt: string | null;
  exportedFrom: string | null;
  rowCounts: Record<string, number> | null;
  checksum: string | null;
}

export interface BackupEntry {
  path: string;
  name: string;
  size: number;
  createdAt: string;
}

export interface ImportResult {
  ok: true;
  metadata: DbMetadataView;
  backupPath: string;
}

interface BackupContextValue {
  serverPath: string | null;
  audit: { problems: AuditProblem[]; problemCount: number; checkedAt: string } | null;
  metadata: DbMetadataView | null;
  backups: BackupEntry[];
  download: () => Promise<void>;
  downloadCsv: (scope?: { ledgerId?: string; month?: string }) => Promise<void>;
  importFile: (file: File) => Promise<ImportResult>;
  backupNow: () => Promise<{ path: string }>;
  refreshBackups: () => Promise<void>;
  restore: (name: string) => Promise<ImportResult>;
  refreshMetadata: () => Promise<void>;
}

const noop = async () => {};

const BackupContext = createContext<BackupContextValue>({
  serverPath: null,
  audit: null,
  metadata: null,
  backups: [],
  download: noop,
  downloadCsv: noop,
  importFile: async () => ({ ok: true, metadata: {} as DbMetadataView, backupPath: '' }),
  backupNow: async () => ({ path: '' }),
  refreshBackups: noop,
  restore: async () => ({ ok: true, metadata: {} as DbMetadataView, backupPath: '' }),
  refreshMetadata: noop,
});

export function useBackup(): BackupContextValue {
  return useContext(BackupContext);
}

export function SqliteBackupProvider({ children }: { children: React.ReactNode }) {
  const [serverPath, setServerPath] = useState<string | null>(null);
  const [audit, setAudit] = useState<{ problems: AuditProblem[]; problemCount: number; checkedAt: string } | null>(null);
  const [metadata, setMetadata] = useState<DbMetadataView | null>(null);
  const [backups, setBackups] = useState<BackupEntry[]>([]);

  const refreshMetadata = useCallback(async () => {
    try {
      const res = await fetch(`${base}/api/export/metadata`);
      if (!res.ok) return;
      const data = (await res.json()) as DbMetadataView;
      setMetadata(data);
    } catch (err) {
      console.error('Could not read export metadata', err);
    }
  }, []);

  const refreshBackups = useCallback(async () => {
    try {
      const res = await fetch(`${base}/api/backups`);
      if (!res.ok) return;
      const data = (await res.json()) as { backups: BackupEntry[] };
      setBackups(data.backups);
    } catch (err) {
      console.error('Could not list backups', err);
    }
  }, []);

  useEffect(() => {
    let cancelled = false;
    void fetchDbInfo()
      .then((info) => {
        if (!cancelled) {
          setServerPath(info.path);
          setAudit(info.audit);
        }
      })
      .catch((err) => console.error('Could not read db info', err));
    void fetch(`${base}/api/export/metadata`)
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => {
        if (!cancelled && data) setMetadata(data as DbMetadataView);
      })
      .catch((err) => console.error('Could not read export metadata', err));
    void fetch(`${base}/api/backups`)
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => {
        if (!cancelled && data) setBackups((data as { backups: BackupEntry[] }).backups);
      })
      .catch((err) => console.error('Could not list backups', err));
    return () => {
      cancelled = true;
    };
  }, []);

  // Always pack: DB + receipts + manifest. The server route still supports
  // the bare-DB path via the `withAttachments=0` query for any external
  // tooling, but the in-app download is standardised on `.finch`.
  const download = useCallback(async () => {
    const res = await fetch(`${base}/api/export?withAttachments=1`);
    if (!res.ok) throw new Error(`Export failed (${res.status})`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    const { downloadBytes } = await import('@/lib/db/storage');
    const ts = new Date().toISOString().replace(/[:.]/g, '-').replace(/-(\d{3})Z$/, 'Z');
    downloadBytes(bytes, `finch-${ts}.finch`, 'application/zip');
  }, []);

  // Optional scope narrows the export to one ledger and/or month; omitted = the
  // full all-ledgers dump. The filename mirrors the server's scoped name.
  const downloadCsv = useCallback(async (scope?: { ledgerId?: string; month?: string }) => {
    const params = new URLSearchParams();
    if (scope?.ledgerId) params.set('ledger', scope.ledgerId);
    if (scope?.month) params.set('month', scope.month);
    const qs = params.toString();
    const res = await fetch(`${base}/api/export/transactions${qs ? `?${qs}` : ''}`);
    if (!res.ok) throw new Error(`CSV export failed (${res.status})`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    const { downloadBytes } = await import('@/lib/db/storage');
    const suffix = [scope?.ledgerId, scope?.month].filter(Boolean).join('-');
    downloadBytes(bytes, suffix ? `finch-transactions-${suffix}.csv` : 'finch-transactions.csv', 'text/csv;charset=utf-8');
  }, []);

  const importFile = useCallback(
    async (file: File): Promise<ImportResult> => {
      const form = new FormData();
      form.append('file', file);
      const res = await fetch(`${base}/api/import`, { method: 'POST', body: form });
      const data = (await res.json()) as ImportResult | { error: string };
      if (!res.ok || 'error' in data) {
        throw new Error('error' in data ? data.error : `Import failed (${res.status})`);
      }
      await Promise.all([refreshMetadata(), refreshBackups()]);
      return data;
    },
    [refreshMetadata, refreshBackups],
  );

  const backupNow = useCallback(async (): Promise<{ path: string }> => {
    const res = await fetch(`${base}/api/backups`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ force: true }),
    });
    const data = (await res.json()) as { path?: string; error?: string };
    if (!res.ok || data.error) throw new Error(data.error ?? `Backup failed (${res.status})`);
    await refreshBackups();
    return { path: data.path! };
  }, [refreshBackups]);

  const restore = useCallback(
    async (name: string): Promise<ImportResult> => {
      const res = await fetch(`${base}/api/restore-backup`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name }),
      });
      const data = (await res.json()) as ImportResult | { error: string };
      if (!res.ok || 'error' in data) {
        throw new Error('error' in data ? data.error : `Restore failed (${res.status})`);
      }
      await Promise.all([refreshMetadata(), refreshBackups()]);
      return data;
    },
    [refreshMetadata, refreshBackups],
  );

  return (
    <BackupContext.Provider
      value={{
        serverPath,
        audit,
        metadata,
        backups,
        download,
        downloadCsv,
        importFile,
        backupNow,
        refreshBackups,
        restore,
        refreshMetadata,
      }}
    >
      {children}
    </BackupContext.Provider>
  );
}
