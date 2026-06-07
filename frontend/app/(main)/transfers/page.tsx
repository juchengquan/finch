'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { EmptyState } from '@/components/empty-state';
import { fmtNative } from '@/lib/data';
import { useLedger } from '@/components/ledger-provider';
import { RowActions } from '@/components/RowActions';
import { useFinanceStore } from '@/lib/store';
import { selectTransfers } from '@/lib/select';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

type Option = { id: string; name: string };

export default function TransfersPage() {
  const { active, activeId } = useLedger();
  const t = useTranslations('transfers');
  const tCommon = useTranslations('common');
  const createTransfer = useFinanceStore((s) => s.createTransfer);
  const updateTransfer = useFinanceStore((s) => s.updateTransfer);
  const deleteTransfer = useFinanceStore((s) => s.deleteTransfer);
  const allTxns = useFinanceStore((s) => s.transactions);
  const accountRows = useFinanceStore((s) => s.accounts);

  const transfers = selectTransfers(allTxns, accountRows, activeId);
  const accounts: Option[] = accountRows
    .filter((a) => a.ledgerId === activeId)
    .map((a) => ({ id: a.id, name: a.name }));

  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [received, setReceived] = useState('');
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [time, setTime] = useState(() => new Date().toTimeString().slice(0, 5));
  const [editing, setEditing] = useState<{
    id: string;
    fromAmount: string;
    toAmount: string;
    fromCurrency: string;
    toCurrency: string;
    date: string;
    time: string;
    note: string;
  } | null>(null);

  const fromCurrency = accountRows.find((a) => a.id === from)?.currency ?? '';
  const toCurrency = accountRows.find((a) => a.id === to)?.currency ?? '';
  const newIsCrossCurrency = !!fromCurrency && !!toCurrency && fromCurrency !== toCurrency;

  const submitEdit = () => {
    if (!editing) return;
    const fromValue = parseFloat(editing.fromAmount);
    if (!fromValue || fromValue <= 0) return void toast.error(t('editDialog.errors.sent'));
    const isCross = editing.fromCurrency !== editing.toCurrency;
    const toValue = isCross ? parseFloat(editing.toAmount) : fromValue;
    if (isCross && (!toValue || toValue <= 0)) return void toast.error(t('editDialog.errors.received'));
    updateTransfer(editing.id, {
      fromAmount: fromValue,
      toAmount: isCross ? toValue : undefined,
      date: editing.date,
      time: editing.time || null,
      note: editing.note.trim() || null,
    });
    toast.success(t('editDialog.updatedToast'));
    setEditing(null);
  };

  // Default the from/to selects to the first two accounts once they're loaded.
  if (accounts.length && !accounts.some((a) => a.id === from)) setFrom(accounts[0].id);
  if (accounts.length > 1 && !accounts.some((a) => a.id === to)) setTo(accounts[1].id);

  const save = () => {
    const value = parseFloat(amount);
    if (!value || value <= 0) return toast.error(t('newDialog.errors.amount'));
    if (from === to) return toast.error(t('newDialog.errors.sameAccount'));
    const recv = newIsCrossCurrency && received ? parseFloat(received) : undefined;
    if (newIsCrossCurrency && received && (!recv || recv <= 0)) return toast.error(t('newDialog.errors.received'));
    createTransfer({ fromAccountId: from, toAccountId: to, fromAmount: value, toAmount: recv, date, time: time || undefined });
    toast.success(t('newDialog.createdToast'));
    setAmount('');
    setReceived('');
  };

  const newTransferDialog = (
    <Dialog>
      <DialogTrigger asChild>
        <IconButton icon="plus" aria-label={t('newAria')} />
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('newDialog.title')}</DialogTitle>
          <DialogDescription>{t('newDialog.description', { ledger: active.name })}</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label>{t('newDialog.from')}</Label>
            <Select value={from} onValueChange={setFrom}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {accounts.map((a) => (
                  <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>{t('newDialog.to')}</Label>
            <Select value={to} onValueChange={setTo}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {accounts.map((a) => (
                  <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-muted-foreground font-mono text-xs w-10">{fromCurrency || t('newDialog.sentFallback')}</span>
            <Input type="number" inputMode="decimal" placeholder="0.00" value={amount} onChange={(e) => setAmount(e.target.value)} autoFocus />
            <Input type="date" aria-label={t('newDialog.dateAria')} value={date} onChange={(e) => setDate(e.target.value)} className="w-40" />
            <Input type="time" aria-label={t('newDialog.timeAria')} value={time} onChange={(e) => setTime(e.target.value)} className="w-28" />
          </div>
          {newIsCrossCurrency && (
            <div className="flex items-center gap-2">
              <span className="text-muted-foreground font-mono text-xs w-10">{toCurrency}</span>
              <Input
                type="number"
                inputMode="decimal"
                placeholder={t('newDialog.receivedPlaceholder')}
                value={received}
                onChange={(e) => setReceived(e.target.value)}
              />
            </div>
          )}
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">{tCommon('cancel')}</Button>
          </DialogClose>
          <DialogClose asChild>
            <Button onClick={save}>{t('newDialog.submit')}</Button>
          </DialogClose>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  return (
    <MobilePage header={<ScreenHeader title={t('title')} trailing={newTransferDialog} />}>
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-5">
          <SchemaChip label="entries" />
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {transfers.length} <span className="text-muted-foreground italic">{t('transfers')}</span>
          </div>
          <div className="text-secondary-foreground mt-1.5 text-[13px]">
            {t('intro')}
          </div>
        </div>

        {transfers.length === 0 && (
          <EmptyState
            icon="swap"
            title={t('empty.title')}
            description={t('empty.description')}
          />
        )}

        {transfers.map((tg) => (
          <div
            key={tg.id}
            className="border-border bg-card mb-2.5 flex items-center gap-3 rounded-[14px] border p-4"
          >
            <div className="bg-secondary text-secondary-foreground flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-[16px]">
              <Icon name="split" size={16} stroke={2} />
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-baseline justify-between gap-2">
                <div className="truncate text-sm font-medium">
                  {tg.fromName ?? '—'} → {tg.toName ?? '—'}
                </div>
                <div className="font-sans text-[15px] font-medium tabular-nums">
                  {fmtNative(tg.amount, tg.fromCurrency)}
                </div>
              </div>
              <div className="text-muted-foreground mt-0.5 text-[11px]">
                {tg.date.replace(/-/g, '/')}{tg.time ? ` ${tg.time}` : ''}
                {tg.fromCurrency !== tg.toCurrency && tg.amount > 0
                  ? ` · → ${fmtNative(tg.toAmount, tg.toCurrency)} @ ${(tg.toAmount / tg.amount).toFixed(4)}`
                  : ''}
                {tg.note ? ` · ${tg.note}` : ''}
              </div>
            </div>
            <RowActions
              onEdit={() => setEditing({
                id: tg.id,
                fromAmount: String(tg.amount),
                toAmount: String(tg.toAmount),
                fromCurrency: tg.fromCurrency,
                toCurrency: tg.toCurrency,
                date: tg.date,
                time: tg.time ?? '',
                note: tg.note ?? '',
              })}
              onDelete={() => { deleteTransfer(tg.id); toast.success(t('row.deletedToast')); }}
              confirmTitle={t('row.deleteTitle')}
              confirmDescription={t('row.deleteDescription', { from: tg.fromName ?? '—', to: tg.toName ?? '—' })}
            />
          </div>
        ))}
      </div>

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('editDialog.title')}</DialogTitle>
            <DialogDescription>{t('editDialog.description')}</DialogDescription>
          </DialogHeader>
          {editing && (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>{t('editDialog.sent', { currency: editing.fromCurrency })}</Label>
                <Input type="number" inputMode="decimal" value={editing.fromAmount} onChange={(e) => setEditing((p) => (p ? { ...p, fromAmount: e.target.value } : p))} autoFocus />
              </div>
              {editing.fromCurrency !== editing.toCurrency && (
                <div className="flex flex-col gap-1.5">
                  <Label>{t('editDialog.received', { currency: editing.toCurrency })}</Label>
                  <Input type="number" inputMode="decimal" value={editing.toAmount} onChange={(e) => setEditing((p) => (p ? { ...p, toAmount: e.target.value } : p))} />
                  {(() => {
                    const f = parseFloat(editing.fromAmount);
                    const ta = parseFloat(editing.toAmount);
                    if (!f || !ta) return null;
                    return (
                      <div className="text-muted-foreground text-[11px]">
                        {t('editDialog.effectiveRate', { rate: (ta / f).toFixed(6), to: editing.toCurrency, from: editing.fromCurrency })}
                      </div>
                    );
                  })()}
                </div>
              )}
              <div className="grid grid-cols-2 gap-3">
                <div className="flex flex-col gap-1.5">
                  <Label>{t('editDialog.date')}</Label>
                  <Input type="date" value={editing.date} onChange={(e) => setEditing((p) => (p ? { ...p, date: e.target.value } : p))} />
                </div>
                <div className="flex flex-col gap-1.5">
                  <Label>{t('editDialog.time')}</Label>
                  <Input type="time" value={editing.time} onChange={(e) => setEditing((p) => (p ? { ...p, time: e.target.value } : p))} />
                </div>
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>{t('editDialog.noteOptional')}</Label>
                <Input value={editing.note} onChange={(e) => setEditing((p) => (p ? { ...p, note: e.target.value } : p))} />
              </div>
            </div>
          )}
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={submitEdit}>{tCommon('save')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
