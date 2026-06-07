'use client';

import { useState } from 'react';
import Link from 'next/link';
import { Check } from 'lucide-react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Icon } from '@/components/primitives';
import { useLedger } from '@/components/ledger-provider';
import { useCurrency } from '@/components/currency-provider';
import { useFinanceStore } from '@/lib/store';
import { CURRENCIES as CURRENCY_RECORD } from '@/lib/data';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { cn } from '@/lib/utils';

const CURRENCY_CODES = Object.keys(CURRENCY_RECORD).sort();
const DEFAULT_COLOR = '#c96442';

export function LedgerSwitcher({
  sidebarOpen = true,
  className,
}: {
  sidebarOpen?: boolean;
  className?: string;
}) {
  const { ledgers, active, activeId, setActiveId } = useLedger();
  // The active chip shows the display currency (what amounts are shown in); the
  // dropdown list shows each ledger's own base currency.
  const { currency } = useCurrency();
  const [createOpen, setCreateOpen] = useState(false);
  const t = useTranslations('ledgerSwitcher');

  return (
    <>
    <DropdownMenu>
      {sidebarOpen ? (
        <div
          className={cn(
            'border-sidebar-border flex items-center gap-0.5 rounded-lg border pr-1',
            className,
          )}
        >
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              aria-label={t('switchAria')}
              // pl-[9px] = the usual 10px inset minus the chip's 1px border, so the
              // dot rides the same icon column (x=30) as the collapsed state and
              // the nav icons — no shift when the sidebar toggles.
              className="hover:bg-sidebar-accent flex min-w-0 flex-1 items-center gap-2.5 rounded-l-lg py-1.5 pl-[9px] text-left transition-colors"
            >
              <span className="flex size-4 shrink-0 items-center justify-center">
                <span
                  className="size-2.5 rounded-full"
                  style={{ background: active.color }}
                />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[13px] font-medium">{active.name}</span>
                <span className="text-muted-foreground block font-mono text-[10px]">
                  {currency}
                </span>
              </span>
              <Icon
                name="swap"
                size={14}
                className="text-muted-foreground mr-0.5 shrink-0"
              />
            </button>
          </DropdownMenuTrigger>
          <Link
            href="/settings/ledger"
            aria-label={t('settingsAria')}
            title={t('settingsAria')}
            className="text-muted-foreground hover:bg-sidebar-accent hover:text-foreground flex size-7 shrink-0 items-center justify-center rounded-md transition-colors"
          >
            <Icon name="cog" size={15} />
          </Link>
        </div>
      ) : (
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label="Switch ledger"
            title={active.name}
            className={cn(
              // border-transparent + pl-[9px] mirror the expanded chip's border
              // geometry so the dot stays on the icon column (x=30).
              'hover:bg-sidebar-accent flex w-full items-center rounded-md border border-transparent py-1.5 pr-2.5 pl-[9px] transition-colors',
              className,
            )}
          >
            {/* shrink-0: the collapsed content box is narrower than 16px (the
                aside's right border eats 1px of w-[60px]), so without it this
                box shrinks and the dot lands at x=29.5 instead of 30. */}
            <span className="flex size-4 shrink-0 items-center justify-center">
              <span className="size-2.5 rounded-full" style={{ background: active.color }} />
            </span>
            {/* Invisible zero-width replica of the expanded chip's two text lines:
                keeps this trigger exactly as tall as the chip, so the dot doesn't
                sink when the sidebar collapses (the footer is bottom-anchored). */}
            <span aria-hidden className="invisible w-0">
              <span className="block text-[13px] font-medium">{active.name}</span>
              <span className="block font-mono text-[10px]">{currency}</span>
            </span>
          </button>
        </DropdownMenuTrigger>
      )}
      <DropdownMenuContent side="top" align="start" className="w-64">
        <DropdownMenuLabel className="font-serif text-base italic">{t('header')}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {ledgers.map((l) => (
          <DropdownMenuItem
            key={l.id}
            onSelect={() => setActiveId(l.id)}
            className="items-start gap-2.5 py-2"
          >
            <span
              className="mt-1 size-2.5 shrink-0 rounded-full"
              style={{ background: l.color }}
            />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 text-[13px] font-medium">
                <span className="truncate">{l.name}</span>
                <span className="text-muted-foreground font-mono text-[10px]">{l.base}</span>
              </div>
              {l.tagline && (
                <div className="text-muted-foreground truncate text-xs">{l.tagline}</div>
              )}
              {/* Live counts straight from the projected row (commit 1's
                  subselects). Replaces the previous static-JSON numbers. */}
              <div className="text-muted-foreground/80 font-mono text-[10px]">
                {t('accountsCount', { count: l.accounts })} · {t('txnsCount', { count: l.txns })}
              </div>
            </div>
            {l.id === activeId && <Check className="text-primary mt-0.5 size-4 shrink-0" />}
          </DropdownMenuItem>
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuItem
          onSelect={(e) => {
            // Stop the menu from auto-closing when we open the dialog; the
            // close happens via the trigger pattern but the dialog handler
            // wants to mount cleanly.
            e.preventDefault();
            setCreateOpen(true);
          }}
          className="text-muted-foreground gap-2.5 py-2"
        >
          <Icon name="plus" size={16} className="shrink-0" />
          <span className="text-[13px] font-medium">{t('newLedger')}</span>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
    <NewLedgerDialog open={createOpen} onOpenChange={setCreateOpen} />
    </>
  );
}

function NewLedgerDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const createLedger = useFinanceStore((s) => s.createLedger);
  const { setActiveId } = useLedger();
  const t = useTranslations('ledgerSwitcher.newDialog');
  const tCommon = useTranslations('common');
  const [name, setName] = useState('');
  const [base, setBase] = useState('USD');
  const [color, setColor] = useState(DEFAULT_COLOR);
  const [tagline, setTagline] = useState('');
  const [busy, setBusy] = useState(false);

  const reset = () => {
    setName('');
    setBase('USD');
    setColor(DEFAULT_COLOR);
    setTagline('');
    setBusy(false);
  };

  const submit = () => {
    const trimmed = name.trim();
    if (!trimmed) {
      toast.error(t('nameRequired'));
      return;
    }
    setBusy(true);
    try {
      const id = createLedger({
        name: trimmed,
        base,
        color,
        tagline: tagline.trim() || null,
      });
      // Land the user in the new (empty) book immediately.
      setActiveId(id);
      toast.success(t('createdToast', { name: trimmed }), { description: t('createdDescription') });
      reset();
      onOpenChange(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t('createFailure'));
      setBusy(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        if (!o) reset();
        onOpenChange(o);
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('title')}</DialogTitle>
          <DialogDescription>{t('description')}</DialogDescription>
        </DialogHeader>
        <div className="grid gap-3 py-2">
          <div className="grid gap-1.5">
            <Label htmlFor="new-ledger-name">{t('name')}</Label>
            <Input
              id="new-ledger-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t('namePlaceholder')}
              autoFocus
              maxLength={40}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="grid gap-1.5">
              <Label htmlFor="new-ledger-base">{t('base')}</Label>
              <Select value={base} onValueChange={setBase}>
                <SelectTrigger id="new-ledger-base">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {CURRENCY_CODES.map((c) => (
                    <SelectItem key={c} value={c}>{c}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="grid gap-1.5">
              <Label htmlFor="new-ledger-color">{t('color')}</Label>
              <div className="flex items-center gap-2">
                <input
                  id="new-ledger-color"
                  type="color"
                  value={color}
                  onChange={(e) => setColor(e.target.value)}
                  className="border-border h-9 w-12 cursor-pointer rounded-md border bg-transparent"
                />
                <span className="text-muted-foreground font-mono text-[11px]">{color}</span>
              </div>
            </div>
          </div>
          <div className="grid gap-1.5">
            <Label htmlFor="new-ledger-tagline">{t('tagline')}</Label>
            <Input
              id="new-ledger-tagline"
              value={tagline}
              onChange={(e) => setTagline(e.target.value)}
              placeholder={t('taglinePlaceholder')}
              maxLength={80}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={busy}>
            {tCommon('cancel')}
          </Button>
          <Button onClick={submit} disabled={busy || !name.trim()}>
            {busy ? t('creating') : t('create')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
