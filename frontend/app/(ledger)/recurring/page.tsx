'use client';

import Link from 'next/link';
import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { RowActions } from '@/components/RowActions';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useLedger } from '@/components/ledger-provider';
import { fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';

const TYPES = ['expense', 'income', 'transfer'];
const FREQUENCIES = ['weekly', 'monthly', 'quarterly', 'yearly'];
const EMPTY = { name: '', type: 'expense', amount: '', frequency: 'monthly', dayOfMonth: '1', account: '', from: '', autoPost: true };

export default function RecurringPage() {
  const { activeId } = useLedger();
  const recurring = useFinanceStore((s) => s.recurring);
  const createRecurring = useFinanceStore((s) => s.createRecurring);
  const deleteRecurring = useFinanceStore((s) => s.deleteRecurring);

  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState(EMPTY);
  const openCreate = () => { setDraft(EMPTY); setOpen(true); };
  const submit = () => {
    const name = draft.name.trim();
    if (!name) return void toast.error('Enter a template name');
    if (!draft.account.trim()) return void toast.error('Enter an account');
    createRecurring({
      name,
      type: draft.type,
      amount: draft.amount.trim() === '' ? null : Number(draft.amount),
      frequency: draft.frequency,
      dayOfMonth: Number(draft.dayOfMonth) || 1,
      account: draft.account.trim(),
      from: draft.type === 'transfer' ? draft.from.trim() || undefined : undefined,
      autoPost: draft.autoPost,
      ledgerId: activeId,
    });
    toast.success('Template created', { description: name });
    setOpen(false);
  };

  return (
    <MobilePage
      header={<ScreenHeader title="Recurring" trailing={<IconButton icon="plus" aria-label="New template" onClick={openCreate} />} />}
    >
      <div className="px-5 pb-[120px]">
        <div className="flex items-end justify-between px-1 pb-5">
          <div>
            <SchemaChip label="recurring_templates"/>
            <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
              {recurring.length} <span className="italic text-muted-foreground">templates</span>
            </div>
            <div className="mt-1.5 text-[13px] text-secondary-foreground">
              Scheduled income & bills. Tap one to edit its splits.
            </div>
          </div>
          <Button variant="outline" size="sm" className="h-8 shrink-0" onClick={openCreate}>
            <Icon name="plus" size={13} />New
          </Button>
        </div>

        {recurring.map((t) => (
          <div
            key={t.id}
            className="border-border bg-card mb-2.5 flex items-center gap-3 rounded-[14px] border p-4"
          >
            <Link
              href={`/recurring/${t.id}`}
              className="flex min-w-0 flex-1 items-center gap-3 text-inherit no-underline"
            >
              <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-[16px] bg-secondary text-secondary-foreground">
                <Icon name="sync" size={16} stroke={2}/>
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-2">
                  <div className="truncate text-sm font-medium">{t.name}</div>
                  <div className="font-sans text-[15px] font-medium tabular-nums">
                    {t.varies ? 'Varies' : fmtNative(t.amount ?? 0, 'SGD')}
                  </div>
                </div>
                <div className="mt-0.5 flex items-center gap-1.5 text-[11px] text-muted-foreground">
                  {t.frequency} · day {t.dayOfMonth} · next {t.nextRun}
                  {t.autoPost ? (
                    <span className="rounded bg-secondary px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px] text-secondary-foreground">AUTO</span>
                  ) : null}
                </div>
              </div>
            </Link>
            <RowActions
              onDelete={() => { deleteRecurring(t.id); toast.success('Recurring template deleted', { description: t.name }); }}
              confirmTitle={`Delete ${t.name}?`}
              confirmDescription="This removes the recurring template and its splits. Already-posted transactions are kept."
            />
          </div>
        ))}
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>New recurring template</DialogTitle>
            <DialogDescription>A scheduled bill, subscription, income or transfer.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>Name</Label>
              <Input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="e.g. Netflix" autoFocus />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Type</Label>
                <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v })}>
                  <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Amount</Label>
                <Input type="number" inputMode="decimal" value={draft.amount} onChange={(e) => setDraft({ ...draft, amount: e.target.value })} placeholder="0.00" />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Frequency</Label>
                <Select value={draft.frequency} onValueChange={(v) => setDraft({ ...draft, frequency: v })}>
                  <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {FREQUENCIES.map((f) => <SelectItem key={f} value={f}>{f}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Day of month</Label>
                <Input type="number" inputMode="numeric" min={1} max={31} value={draft.dayOfMonth} onChange={(e) => setDraft({ ...draft, dayOfMonth: e.target.value })} />
              </div>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>{draft.type === 'transfer' ? 'To account' : 'Account'}</Label>
              <Input value={draft.account} onChange={(e) => setDraft({ ...draft, account: e.target.value })} placeholder="e.g. Amex Gold" />
            </div>
            {draft.type === 'transfer' && (
              <div className="flex flex-col gap-1.5">
                <Label>From account</Label>
                <Input value={draft.from} onChange={(e) => setDraft({ ...draft, from: e.target.value })} placeholder="e.g. Chase Checking" />
              </div>
            )}
            <div className="flex items-center justify-between">
              <Label htmlFor="rt-new-autopost">Auto-post</Label>
              <Switch id="rt-new-autopost" checked={draft.autoPost} onCheckedChange={(v) => setDraft({ ...draft, autoPost: v })} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submit}>Create</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
