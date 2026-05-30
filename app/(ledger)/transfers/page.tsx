'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
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
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [editing, setEditing] = useState<{ id: string; amount: string; date: string; note: string } | null>(null);

  const submitEdit = () => {
    if (!editing) return;
    const value = parseFloat(editing.amount);
    if (!value || value <= 0) return void toast.error('Enter an amount');
    updateTransfer(editing.id, { amount: value, date: editing.date, note: editing.note.trim() || null });
    toast.success('Transfer updated');
    setEditing(null);
  };

  // Default the from/to selects to the first two accounts once they're loaded.
  if (accounts.length && !accounts.some((a) => a.id === from)) setFrom(accounts[0].id);
  if (accounts.length > 1 && !accounts.some((a) => a.id === to)) setTo(accounts[1].id);

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
                  {fmtNative(tg.amount, tg.fromCurrency)}
                </div>
              </div>
              <div className="text-muted-foreground mt-0.5 text-[11px]">
                {tg.date.replace(/-/g, '/')}
                {tg.fromCurrency !== tg.toCurrency && tg.amount > 0
                  ? ` · → ${fmtNative(tg.toAmount, tg.toCurrency)} @ ${(tg.toAmount / tg.amount).toFixed(4)}`
                  : ''}
                {tg.note ? ` · ${tg.note}` : ''}
              </div>
            </div>
            <RowActions
              onEdit={() => setEditing({ id: tg.id, amount: String(tg.amount), date: tg.date, note: tg.note ?? '' })}
              onDelete={() => { deleteTransfer(tg.id); toast.success('Transfer deleted'); }}
              confirmTitle="Delete this transfer?"
              confirmDescription={`Removes both legs (${tg.fromName ?? '—'} → ${tg.toName ?? '—'}) and restores the account balances.`}
            />
          </div>
        ))}
      </div>

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit transfer</DialogTitle>
            <DialogDescription>Adjust the amount, date or note. Balances are recomputed.</DialogDescription>
          </DialogHeader>
          {editing && (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Amount</Label>
                <Input type="number" inputMode="decimal" value={editing.amount} onChange={(e) => setEditing((p) => (p ? { ...p, amount: e.target.value } : p))} autoFocus />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Date</Label>
                <Input type="date" value={editing.date} onChange={(e) => setEditing((p) => (p ? { ...p, date: e.target.value } : p))} />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Note (optional)</Label>
                <Input value={editing.note} onChange={(e) => setEditing((p) => (p ? { ...p, note: e.target.value } : p))} />
              </div>
            </div>
          )}
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitEdit}>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
