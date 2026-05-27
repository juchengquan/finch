'use client';

import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { fmtNative } from '@/lib/data';
import { useLedger } from '@/components/ledger-provider';
import { useDb } from '@/components/db-provider';
import { useFinanceStore } from '@/lib/store';
import { listTransfers, type Transfer } from '@/lib/db/queries/transfers';
import { listAccounts } from '@/lib/db/queries/accounts';
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
  const { exec, version } = useDb();
  const createTransfer = useFinanceStore((s) => s.createTransfer);

  const [transfers, setTransfers] = useState<Transfer[]>([]);
  const [accounts, setAccounts] = useState<Option[]>([]);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));

  useEffect(() => {
    if (!exec) return;
    let cancelled = false;
    Promise.all([listTransfers(exec, activeId), listAccounts(exec, activeId)])
      .then(([tg, accts]) => {
        if (cancelled) return;
        const opts = accts.map((a) => ({ id: a.id, name: a.name }));
        setTransfers(tg);
        setAccounts(opts);
        setFrom((prev) => prev || opts[0]?.id || '');
        setTo((prev) => prev || opts[1]?.id || '');
      })
      .catch((err) => console.error('Could not load transfers from DB', err));
    return () => {
      cancelled = true;
    };
  }, [exec, version, activeId]);

  const save = () => {
    const value = parseFloat(amount);
    if (!value || value <= 0) return toast.error('Enter an amount');
    if (from === to) return toast.error('Pick two different accounts');
    createTransfer({ fromAccountId: from, toAccountId: to, amount: value, date });
    toast.success('Transfer created');
    setAmount('');
  };

  const newTransferDialog = (
    <Dialog>
      <DialogTrigger asChild>
        <IconButton icon="plus" aria-label="New transfer" />
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New transfer</DialogTitle>
          <DialogDescription>Move money between two accounts in {active.name}.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label>From</Label>
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
            <Label>To</Label>
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
            <span className="text-muted-foreground font-serif text-xl">$</span>
            <Input type="number" inputMode="decimal" placeholder="0.00" value={amount} onChange={(e) => setAmount(e.target.value)} autoFocus />
            <Input type="date" aria-label="Date" value={date} onChange={(e) => setDate(e.target.value)} className="w-40" />
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <DialogClose asChild>
            <Button onClick={save}>Transfer</Button>
          </DialogClose>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  return (
    <MobilePage header={<ScreenHeader title="Transfers" trailing={newTransferDialog} />}>
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-5">
          <SchemaChip label="transfer_groups" />
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {transfers.length} <span className="text-muted-foreground italic">transfers</span>
          </div>
          <div className="text-secondary-foreground mt-1.5 text-[13px]">
            Cross-account moves. Each creates a linked pair of transactions.
          </div>
        </div>

        {transfers.length === 0 && (
          <div className="text-muted-foreground rounded-[14px] border border-dashed py-10 text-center text-sm">
            No transfers yet — use the + button to create one.
          </div>
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
                  {fmtNative(tg.amount, active.base)}
                </div>
              </div>
              <div className="text-muted-foreground mt-0.5 text-[11px]">
                {tg.date.slice(5).replace('-', '/')}
                {tg.note ? ` · ${tg.note}` : ''}
              </div>
            </div>
          </div>
        ))}
      </div>
    </MobilePage>
  );
}
