'use client';

import { useRef, useState } from 'react';
import { Icon, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { SettingsItem } from '@/components/SettingsItem';
import { MobileTabsEditor } from '@/components/MobileTabsEditor';
import { SettingsTabs } from '@/components/settings-tabs';
import { ThemeToggle } from '@/components/theme-toggle';
import { useCurrency, type Currency } from '@/components/currency-provider';
import { useBackup, type BackupEntry, type ImportResult, type DbMetadataView } from '@/components/sqlite-backup-provider';
import { useFinanceStore } from '@/lib/store';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

const fmtBytes = (n: number) => {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
};
const fmtDate = (iso: string) => new Date(iso).toLocaleString();

const CURRENCIES: Currency[] = ['USD', 'EUR', 'GBP', 'JPY', 'SGD', 'CNY'];

function Row({ icon, label, children }: { icon: string; label: string; children: React.ReactNode }) {
  return (
    <div className="border-border flex items-center gap-3.5 border-b py-3.5">
      <div className="bg-secondary text-secondary-foreground flex size-[30px] shrink-0 items-center justify-center rounded-full">
        <Icon name={icon} size={14} />
      </div>
      <div className="flex-1 text-sm">{label}</div>
      {children}
    </div>
  );
}

export default function AccountSettingsPage() {
  const { currency, setCurrency } = useCurrency();
  const reset = useFinanceStore((s) => s.reset);
  const backup = useBackup();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [pendingFile, setPendingFile] = useState<{ file: File; metadata: DbMetadataView } | null>(null);
  const [restoreTarget, setRestoreTarget] = useState<BackupEntry | null>(null);
  const [busy, setBusy] = useState(false);

  const onFilePicked = async (file: File) => {
    if (!file) return;
    setBusy(true);
    try {
      // Probe the file's metadata so the confirm dialog can show what it'll
      // replace. We pipe through importFile after the user confirms.
      const probeForm = new FormData();
      probeForm.append('file', file);
      // First pass: a HEAD-style request would be ideal, but the import
      // endpoint validates fully and is fine to call now — we just don't
      // actually swap until the user confirms by clicking "Import". So we
      // do the dry-run via a temporary read of the file's metadata.
      // Implementation note: we use the same validate() the server runs by
      // calling the server with a special header, but that's overkill for
      // V1 — just read the file in the browser and reach for the schema +
      // app_name fields via sql.js if we wanted. For now, defer validation
      // to the actual import and show a generic prompt.
      setPendingFile({
        file,
        metadata: {
          appName: 'finch',
          schemaVersion: '(probed on import)',
          appVersion: '?',
          createdAt: '',
          updatedAt: '',
          exportedAt: null,
          exportedFrom: null,
          rowCounts: null,
          checksum: null,
        },
      });
    } finally {
      setBusy(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const confirmImport = async () => {
    if (!pendingFile) return;
    setBusy(true);
    try {
      const r: ImportResult = await backup.importFile(pendingFile.file);
      toast.success('Database imported', {
        description: `Previous data backed up to ${r.backupPath.split(/[\\/]/).pop()}`,
      });
      setPendingFile(null);
      // Force a fresh server projection by reloading — the server cache was
      // dropped on swap and the store needs to re-hydrate from the new file.
      setTimeout(() => window.location.reload(), 800);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Import failed');
    } finally {
      setBusy(false);
    }
  };

  const confirmRestore = async () => {
    if (!restoreTarget) return;
    setBusy(true);
    try {
      const r = await backup.restore(restoreTarget.name);
      toast.success('Backup restored', {
        description: `Previous data backed up to ${r.backupPath.split(/[\\/]/).pop()}`,
      });
      setRestoreTarget(null);
      setTimeout(() => window.location.reload(), 800);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Restore failed');
    } finally {
      setBusy(false);
    }
  };

  const onBackupNow = async () => {
    setBusy(true);
    try {
      const r = await backup.backupNow();
      toast.success('Backup created', { description: r.path.split(/[\\/]/).pop() });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Backup failed');
    } finally {
      setBusy(false);
    }
  };

  return (
    <MobilePage>
      <ScreenHeader title="Settings" trailing={<SearchButton />} />

      <div className="px-5">
        <SettingsTabs />
      </div>

      <div className="flex items-center gap-3.5 px-5 pb-[22px]">
        <MerchantGlyph name="Alex Morgan" size={64} bg="var(--primary)" fg="var(--primary-foreground)" />
        <div className="flex-1">
          <div className="font-serif text-[22px] -tracking-[0.3px]">Alex Morgan</div>
          <div className="text-muted-foreground text-xs">Personal plan</div>
        </div>
      </div>

      <div className="px-5 pb-28">
        <div className="text-muted-foreground pb-2 font-mono text-[10px] tracking-wider uppercase">
          Preferences
        </div>
        <SettingsItem item={{ label: 'Notifications', toggle: true, icon: 'bell' }} />

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          Appearance
        </div>
        <Row icon="sparkle" label="Theme">
          <ThemeToggle />
        </Row>
        <Row icon="wallet" label="Display currency">
          <Select value={currency} onValueChange={(v) => setCurrency(v as Currency)}>
            <SelectTrigger size="sm" className="w-24">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {CURRENCIES.map((c) => (
                <SelectItem key={c} value={c}>
                  {c}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Row>

        <div className="md:hidden">
          <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
            Bottom bar
          </div>
          <MobileTabsEditor />
          <div className="text-muted-foreground pt-2 text-xs">
            Choose and reorder the four sections in your bottom navigation. The center
            Add button is always shown.
          </div>
        </div>

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          Data
        </div>
        <Row icon="sync" label="Sample data">
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              reset();
              toast.success('Sample data restored');
            }}
          >
            Reset
          </Button>
        </Row>
        <div className="text-muted-foreground pt-2 text-xs">
          Your changes are saved on this device. Reset restores the original sample data.
        </div>

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          Backup & restore
        </div>
        {backup.metadata && (
          <div className="bg-card border-border mb-2 rounded-xl border p-3.5 text-[11px]">
            <div className="text-muted-foreground mb-1.5 font-mono uppercase tracking-wider text-[10px]">Database</div>
            <div className="flex flex-wrap gap-x-4 gap-y-1">
              <span>
                <span className="text-muted-foreground">App:</span> v{backup.metadata.appVersion}
              </span>
              <span>
                <span className="text-muted-foreground">Schema:</span> {backup.metadata.schemaVersion}
              </span>
              <span>
                <span className="text-muted-foreground">Updated:</span> {fmtDate(backup.metadata.updatedAt)}
              </span>
              {backup.metadata.rowCounts && (
                <span>
                  <span className="text-muted-foreground">Rows:</span>{' '}
                  {backup.metadata.rowCounts.transactions ?? 0} txns ·{' '}
                  {backup.metadata.rowCounts.accounts ?? 0} accounts ·{' '}
                  {backup.metadata.rowCounts.categories ?? 0} categories
                </span>
              )}
            </div>
          </div>
        )}
        <Row icon="doc" label="Database file (server)">
          <span className="text-muted-foreground max-w-[60%] truncate text-right font-mono text-[11px]">
            {backup.serverPath ?? '…'}
          </span>
        </Row>
        <Row icon="download" label="Export a copy">
          <Button variant="outline" size="sm" onClick={() => void backup.download()}>
            Download .db
          </Button>
        </Row>
        <Row icon="doc" label="Export transactions">
          <Button variant="outline" size="sm" onClick={() => void backup.downloadCsv()}>
            Download .csv
          </Button>
        </Row>
        <Row icon="upload" label="Import database">
          <input
            ref={fileInputRef}
            type="file"
            accept=".sqlite3,.db,application/x-sqlite3"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void onFilePicked(f);
            }}
          />
          <Button
            variant="outline"
            size="sm"
            disabled={busy}
            onClick={() => fileInputRef.current?.click()}
          >
            Choose file…
          </Button>
        </Row>
        <Row icon="sync" label="Back up now">
          <Button variant="outline" size="sm" disabled={busy} onClick={() => void onBackupNow()}>
            Snapshot
          </Button>
        </Row>
        <Row icon="upload" label="Restore from backup">
          {backup.backups.length === 0 ? (
            <span className="text-muted-foreground text-[11px]">No backups yet</span>
          ) : (
            <Select
              value=""
              onValueChange={(name) => setRestoreTarget(backup.backups.find((b) => b.name === name) ?? null)}
            >
              <SelectTrigger size="sm" className="w-[170px]">
                <SelectValue placeholder="Pick backup" />
              </SelectTrigger>
              <SelectContent>
                {backup.backups.map((b) => (
                  <SelectItem key={b.name} value={b.name}>
                    {fmtDate(b.createdAt)} · {fmtBytes(b.size)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
        </Row>
        <div className="text-muted-foreground pt-2 text-xs">
          Your data lives in a SQLite file on the server and syncs on every change. Importing
          replaces the live file — a snapshot of the current state is saved automatically before
          the swap.
        </div>
      </div>

      <Dialog open={!!pendingFile} onOpenChange={(o) => !o && !busy && setPendingFile(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Import database?</DialogTitle>
            <DialogDescription>
              This will replace your current database with the contents of{' '}
              <span className="font-mono">{pendingFile?.file.name}</span>. A backup of your
              current data will be saved automatically before the swap.
            </DialogDescription>
          </DialogHeader>
          <div className="text-muted-foreground bg-secondary/40 rounded-lg p-3 text-[12px]">
            File size: {pendingFile ? fmtBytes(pendingFile.file.size) : ''}.
            The file is validated (SQLite header, schema version, foreign keys, checksum) before
            it replaces your live database.
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={busy}>Cancel</Button>
            </DialogClose>
            <Button onClick={() => void confirmImport()} disabled={busy}>
              {busy ? 'Importing…' : 'Import'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!restoreTarget} onOpenChange={(o) => !o && !busy && setRestoreTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Restore this backup?</DialogTitle>
            <DialogDescription>
              {restoreTarget && (
                <>
                  Restoring <span className="font-mono">{restoreTarget.name}</span> (
                  {fmtDate(restoreTarget.createdAt)} · {fmtBytes(restoreTarget.size)}) will
                  replace your current database. A snapshot of the current state will be saved
                  automatically before the swap.
                </>
              )}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={busy}>Cancel</Button>
            </DialogClose>
            <Button onClick={() => void confirmRestore()} disabled={busy}>
              {busy ? 'Restoring…' : 'Restore'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
