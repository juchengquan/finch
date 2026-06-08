'use client';

import { useRef, useState } from 'react';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { MobileTabsEditor } from '@/components/MobileTabsEditor';
import { SettingsTabs } from '@/components/settings-tabs';
import { ThemeToggle } from '@/components/theme-toggle';
import { useTranslations } from 'next-intl';
import { useAppLocale, SUPPORTED_LOCALES, type Locale } from '@/components/i18n-provider';
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

// Auto-backup frequency presets (label -> ms). -1 = off. 0 = on every change.
// Values map onto BackupConfigSlice.frequencyMs. Labels come from the
// i18n catalog at render time (`tBackup('frequency.<key>')`), so the
// definition here is just the ms <-> key mapping.
type FreqKey = 'everyChange' | 'hourly' | 'daily' | 'weekly' | 'off';
const FREQ_OPTIONS: { key: FreqKey; ms: number }[] = [
  { key: 'everyChange', ms: 0 },
  { key: 'hourly', ms: 60 * 60 * 1000 },
  { key: 'daily', ms: 24 * 60 * 60 * 1000 },
  { key: 'weekly', ms: 7 * 24 * 60 * 60 * 1000 },
  { key: 'off', ms: -1 },
];
const RETENTION_OPTIONS = [5, 10, 14, 30, 50, 100];

export default function AccountSettingsPage() {
  const reset = useFinanceStore((s) => s.reset);
  const backup = useBackup();
  // I18N_PLAN §4.2 — useAppLocale reads/writes the per-device locale; the
  // useTranslations namespace gives keyed strings for the rows below.
  const { locale, setLocale } = useAppLocale();
  const tSettings = useTranslations('settings.account');
  const tBackup = useTranslations('settings.account.backup');
  const tCommon = useTranslations('common');
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [pendingFile, setPendingFile] = useState<{ file: File; metadata: DbMetadataView } | null>(null);
  const [restoreTarget, setRestoreTarget] = useState<BackupEntry | null>(null);
  const [busy, setBusy] = useState(false);
  // Backup config lives in app_state — travels with the database.
  const backupConfig = useFinanceStore((s) => s.backupConfig);
  const setBackupFrequency = useFinanceStore((s) => s.setBackupFrequency);
  const setBackupRetention = useFinanceStore((s) => s.setBackupRetention);

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
      toast.success(tBackup('importDialog.importSuccess'), {
        description: tBackup('importDialog.importSuccessDescription', { file: r.backupPath.split(/[\\/]/).pop() ?? '' }),
      });
      setPendingFile(null);
      // Force a fresh server projection by reloading — the server cache was
      // dropped on swap and the store needs to re-hydrate from the new file.
      setTimeout(() => window.location.reload(), 800);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : tBackup('importDialog.importFailure'));
    } finally {
      setBusy(false);
    }
  };

  const confirmRestore = async () => {
    if (!restoreTarget) return;
    setBusy(true);
    try {
      const r = await backup.restore(restoreTarget.name);
      toast.success(tBackup('restore.success'), {
        description: tBackup('restore.successDescription', { file: r.backupPath.split(/[\\/]/).pop() ?? '' }),
      });
      setRestoreTarget(null);
      setTimeout(() => window.location.reload(), 800);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : tBackup('restore.failure'));
    } finally {
      setBusy(false);
    }
  };

  const onBackupNow = async () => {
    setBusy(true);
    try {
      const r = await backup.backupNow();
      toast.success(tBackup('backupNow.success'), { description: r.path.split(/[\\/]/).pop() });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : tBackup('backupNowToast.failure'));
    } finally {
      setBusy(false);
    }
  };

  return (
    <MobilePage>
      <ScreenHeader title={tSettings('title')} trailing={<SearchButton />} />

      <div className="px-5">
        <SettingsTabs />
      </div>

      <div className="px-5 pb-28">
        <div className="text-muted-foreground pb-2 font-mono text-[10px] tracking-wider uppercase">
          {tSettings('appearance')}
        </div>
        <Row icon="sparkle" label={tSettings('theme')}>
          <ThemeToggle />
        </Row>
        <Row icon="doc" label={tSettings('language.row')}>
          <Select
            value={locale}
            onValueChange={(v) => setLocale(v as Locale)}
          >
            <SelectTrigger size="sm" className="w-[180px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {SUPPORTED_LOCALES.map((l) => (
                <SelectItem key={l} value={l}>
                  {l === 'en' ? tSettings('language.english') : tSettings('language.chinese')}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Row>

        <div className="md:hidden">
          <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
            {tSettings('bottomBar.section')}
          </div>
          <MobileTabsEditor />
          <div className="text-muted-foreground pt-2 text-xs">
            {tSettings('bottomBar.hint')}
          </div>
        </div>

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          {tSettings('data.section')}
        </div>
        <Row icon="sync" label={tSettings('data.sampleRow')}>
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              reset();
              toast.success(tSettings('data.resetSuccess'));
            }}
          >
            {tSettings('data.resetButton')}
          </Button>
        </Row>
        <div className="text-muted-foreground pt-2 text-xs">
          {tSettings('data.hint')}
        </div>

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          {tBackup('section')}
        </div>
        {backup.metadata && (
          <div className="bg-card border-border mb-2 rounded-xl border p-3.5 text-[11px]">
            <div className="text-muted-foreground mb-1.5 font-mono uppercase tracking-wider text-[10px]">{tSettings('metadata.title')}</div>
            <div className="flex flex-wrap gap-x-4 gap-y-1">
              <span>
                <span className="text-muted-foreground">{tSettings('metadata.app')}</span> v{backup.metadata.appVersion}
              </span>
              <span>
                <span className="text-muted-foreground">{tSettings('metadata.schema')}</span> {backup.metadata.schemaVersion}
              </span>
              <span>
                <span className="text-muted-foreground">{tSettings('metadata.updated')}</span> {fmtDate(backup.metadata.updatedAt)}
              </span>
              {backup.metadata.rowCounts && (
                <span>
                  <span className="text-muted-foreground">{tSettings('metadata.rows')}</span>{' '}
                  {tSettings('metadata.rowsSummary', {
                    txns: backup.metadata.rowCounts.transactions ?? 0,
                    accounts: backup.metadata.rowCounts.accounts ?? 0,
                    categories: backup.metadata.rowCounts.categories ?? 0,
                  })}
                </span>
              )}
            </div>
          </div>
        )}
        <Row icon="doc" label={tBackup('dbInfo.label')}>
          <span className="text-muted-foreground max-w-[60%] truncate text-right font-mono text-[11px]">
            {backup.serverPath ?? tBackup('dbInfo.loading')}
          </span>
        </Row>
        <Row icon="shield-check" label={tBackup('audit.label')}>
          {!backup.audit ? (
            <span className="text-muted-foreground text-xs">{tBackup('audit.loading')}</span>
          ) : backup.audit.problemCount === 0 ? (
            <span className="text-success text-xs">{tBackup('audit.clean')}</span>
          ) : (
            <details className="text-xs">
              <summary className="text-warning cursor-pointer">
                {tBackup('audit.problems', { count: backup.audit.problemCount })}
              </summary>
              <ul className="mt-2 ml-4 list-disc text-muted-foreground">
                {backup.audit.problems.slice(0, 5).map((p, i) => (
                  <li key={i}>
                    <span className="font-mono">{p.code}</span>
                    {p.entryId ? <span> · entry {p.entryId}</span> : null}
                    {p.detail ? <span> · {p.detail}</span> : null}
                  </li>
                ))}
                {backup.audit.problemCount > 5 ? (
                  <li>{tBackup('audit.more', { count: backup.audit.problemCount - 5 })}</li>
                ) : null}
              </ul>
            </details>
          )}
        </Row>
        <Row icon="download" label={tBackup('exportDb.label')}>
          <Button variant="outline" size="sm" onClick={() => void backup.download()}>
            {tBackup('exportDb.button')}
          </Button>
        </Row>
        <Row icon="doc" label={tBackup('exportCsv.label')}>
          <Button variant="outline" size="sm" onClick={() => void backup.downloadCsv()}>
            {tBackup('exportCsv.button')}
          </Button>
        </Row>
        <Row icon="upload" label={tBackup('importDb.label')}>
          <input
            ref={fileInputRef}
            type="file"
            accept=".finch"
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
            {tBackup('importDb.button')}
          </Button>
        </Row>
        <Row icon="clock" label={tBackup('frequency.row')}>
          <Select
            value={String(backupConfig.frequencyMs)}
            onValueChange={(v) => setBackupFrequency(Number(v))}
          >
            <SelectTrigger className="h-8 w-[180px] text-[12px]">
              <SelectValue>
                {tBackup(
                  `frequency.${FREQ_OPTIONS.find((o) => o.ms === backupConfig.frequencyMs)?.key ?? 'off'}`,
                )}
              </SelectValue>
            </SelectTrigger>
            <SelectContent>
              {FREQ_OPTIONS.map((o) => (
                <SelectItem key={o.ms} value={String(o.ms)}>{tBackup(`frequency.${o.key}`)}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Row>
        <Row icon="doc" label={tBackup('retention.row')}>
          <Select
            value={String(backupConfig.retention)}
            onValueChange={(v) => setBackupRetention(Number(v))}
          >
            <SelectTrigger className="h-8 w-[120px] text-[12px]">
              <SelectValue>{tBackup('retention.files', { count: backupConfig.retention })}</SelectValue>
            </SelectTrigger>
            <SelectContent>
              {RETENTION_OPTIONS.map((n) => (
                <SelectItem key={n} value={String(n)}>{tBackup('retention.files', { count: n })}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Row>
        <Row icon="sync" label={tBackup('backupNow.label')}>
          <Button variant="outline" size="sm" disabled={busy} onClick={() => void onBackupNow()}>
            {busy ? tBackup('backupNow.busy') : tBackup('backupNow.button')}
          </Button>
        </Row>
        <Row icon="upload" label={tBackup('restore.row')}>
          {backup.backups.length === 0 ? (
            <span className="text-muted-foreground text-[11px]">{tBackup('restore.noBackups')}</span>
          ) : (
            <Select
              value=""
              onValueChange={(name) => setRestoreTarget(backup.backups.find((b) => b.name === name) ?? null)}
            >
              <SelectTrigger size="sm" className="w-[170px]">
                <SelectValue placeholder={tBackup('restore.pickPlaceholder')} />
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
          {tBackup('hint')}
        </div>
      </div>

      <Dialog open={!!pendingFile} onOpenChange={(o) => !o && !busy && setPendingFile(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{tBackup('importDb.dialogTitle')}</DialogTitle>
            <DialogDescription>
              {tBackup('importDialog.description', { name: pendingFile?.file.name ?? '' })}
            </DialogDescription>
          </DialogHeader>
          <div className="text-muted-foreground bg-secondary/40 rounded-lg p-3 text-[12px]">
            {tBackup('importDialog.fileSize', { size: pendingFile ? fmtBytes(pendingFile.file.size) : '' })}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={busy}>{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={() => void confirmImport()} disabled={busy}>
              {busy ? tBackup('importDb.busy') : tBackup('importDb.confirm')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!restoreTarget} onOpenChange={(o) => !o && !busy && setRestoreTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{tBackup('restore.dialogTitle')}</DialogTitle>
            <DialogDescription>
              {restoreTarget &&
                tBackup('restore.dialogDescriptionDetail', {
                  name: restoreTarget.name,
                  date: fmtDate(restoreTarget.createdAt),
                  size: fmtBytes(restoreTarget.size),
                })}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" disabled={busy}>{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={() => void confirmRestore()} disabled={busy}>
              {busy ? tBackup('restore.busy') : tBackup('restore.confirm')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
