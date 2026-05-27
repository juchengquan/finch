'use client';

import { useParams } from 'next/navigation';
import { useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { Icon, StackedBar } from '@/components/primitives';
import { ScreenHeader, MobilePage, SchemaChip } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { fmtNative } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { mutate } from '@/lib/api-client';
import { cn } from '@/lib/utils';

const FREQUENCIES = ['weekly', 'monthly', 'quarterly', 'yearly'];

const SPLIT_COLOR = (i: number) =>
  i === 0 ? 'var(--primary)' : i === 1 ? 'var(--warning)' : 'var(--success)';

export default function RecurringDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const recurring = useFinanceStore((s) => s.recurring);
  const updateRecurringSplit = useFinanceStore((s) => s.updateRecurringSplit);
  const addRecurringSplit = useFinanceStore((s) => s.addRecurringSplit);
  const removeRecurringSplit = useFinanceStore((s) => s.removeRecurringSplit);
  const updateRecurring = useFinanceStore((s) => s.updateRecurring);
  const t = recurring.find((r) => r.id === id) ?? recurring[0];

  const amount = t.amount ?? 0;
  const splits = t.splits ?? [];
  const totalPct = splits.reduce((sum, s) => sum + (s.pct || 0), 0);

  const [editOpen, setEditOpen] = useState(false);
  const [draft, setDraft] = useState({ name: '', amount: '', frequency: 'monthly', dayOfMonth: '1', autoPost: true });
  const openEdit = () => {
    setDraft({
      name: t.name,
      amount: t.amount == null ? '' : String(t.amount),
      frequency: t.frequency,
      dayOfMonth: String(t.dayOfMonth),
      autoPost: !!t.autoPost,
    });
    setEditOpen(true);
  };
  const submitEdit = () => {
    const n = draft.name.trim();
    if (!n) return void toast.error('Enter a template name');
    updateRecurring(t.id, {
      name: n,
      amount: draft.amount.trim() === '' ? null : Number(draft.amount),
      frequency: draft.frequency,
      dayOfMonth: Number(draft.dayOfMonth) || 1,
      autoPost: draft.autoPost ? 1 : 0,
    });
    toast.success('Template updated', { description: n });
    setEditOpen(false);
  };

  const [splitOpen, setSplitOpen] = useState(false);
  const [splitDraft, setSplitDraft] = useState({ account: '', pct: '' });
  const submitSplit = () => {
    const account = splitDraft.account.trim();
    if (!account) return void toast.error('Enter an account');
    addRecurringSplit(t.id, account, Number(splitDraft.pct) || 0);
    toast.success('Split added', { description: account });
    setSplitDraft({ account: '', pct: '' });
    setSplitOpen(false);
  };

  const [posting, setPosting] = useState(false);
  const post = async () => {
    setPosting(true);
    try {
      const state = await mutate('postRecurring', { templateId: t.id });
      useFinanceStore.setState(state);
      toast.success(`Posted “${t.name}”`, { description: 'Added to transactions.' });
    } catch (err) {
      toast.error((err as Error).message || 'Could not post');
    } finally {
      setPosting(false);
    }
  };

  return (
    <MobilePage header={<ScreenHeader title="Recurring" back backHref="/recurring" />}>
      <div className="px-5 pb-[120px]">
        <div className="mb-5 flex items-center gap-2 text-xs text-muted-foreground md:hidden">
          <Link href="/recurring" className="text-muted-foreground">
            Recurring
          </Link>
          <Icon name="chev" size={11} />
          <span className="font-mono text-foreground">{t.id}</span>
        </div>

        <div className="px-1 pb-[22px]">
          <div className="mt-1 font-serif text-[36px] leading-[1.1] tracking-[-0.8px]">
            <span className="italic text-muted-foreground">{t.name}</span><br/>
            <span className="text-[44px]">{t.varies ? 'Varies' : fmtNative(amount, 'SGD')}</span>
          </div>
          <div className="mt-2 text-xs text-muted-foreground">
            {t.frequency} · day {t.dayOfMonth} — next on <b className="text-secondary-foreground">{t.nextRun}</b> · last {t.lastRun}
          </div>
          <div className="mt-4 flex items-center gap-2">
            <Button onClick={post} disabled={posting || !!t.varies}>
              <Icon name="plus" size={14} />
              {posting ? 'Posting…' : t.varies ? 'Variable — add manually' : 'Post now'}
            </Button>
            <Button variant="outline" onClick={openEdit}>
              <Icon name="edit" size={14} />Edit
            </Button>
          </div>
        </div>

        <div className="mb-2 flex items-baseline justify-between px-1">
          <div className="font-serif text-[20px] italic tracking-[-0.2px]">Splits</div>
          <div className="flex items-center gap-2">
            <SchemaChip label="recurring_splits"/>
            <Button variant="outline" size="sm" className="h-7" onClick={() => { setSplitDraft({ account: '', pct: '' }); setSplitOpen(true); }}>
              <Icon name="plus" size={12} />Add split
            </Button>
          </div>
        </div>
        <div className="px-1 pb-2.5 text-xs text-muted-foreground">
          {splits.length > 0 ? 'Split across accounts. Total must equal 100%.' : 'No splits — the whole amount posts to the account above. Add splits to divide it.'}
        </div>

        {splits.length > 0 && (
          <>
            <div className="mb-2.5 rounded-[14px] border border-border bg-card p-3.5">
              <StackedBar
                slices={splits.map((s, i) => ({ value: s.pct || 0, color: SPLIT_COLOR(i) }))}
                width={310} height={12} radius={6}/>
              <div className="mt-2.5 flex justify-between font-mono text-[10px] text-muted-foreground">
                <span>0%</span><span>50%</span><span>100%</span>
              </div>
            </div>

            {splits.map((s, i) => {
              const splitAmount = amount * (s.pct || 0) / 100;
              return (
                <div key={i} className="mb-2 rounded-[14px] border border-border bg-card p-3.5">
                  <div className="flex items-center gap-3">
                    <div className="h-9 w-2 rounded" style={{ background: SPLIT_COLOR(i) }}/>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-baseline justify-between gap-2">
                        <div className="text-sm font-medium">{s.account}</div>
                        <div className="font-sans text-sm font-medium tabular-nums">{fmtNative(splitAmount, 'SGD')}</div>
                      </div>
                      <div className="mt-1.5 flex items-center justify-between gap-2">
                        <div className="text-[11px] text-muted-foreground">{s.label}</div>
                        <div className="flex items-center gap-1.5">
                          <Input
                            type="number"
                            value={s.pct}
                            min={0}
                            max={100}
                            aria-label={`${s.account} percent`}
                            onChange={(e) => updateRecurringSplit(t.id, i, Number(e.target.value))}
                            className="h-8 w-16 text-right font-mono text-[13px]"
                          />
                          <span className="font-mono text-[11px] text-muted-foreground">%</span>
                          <button
                            type="button"
                            aria-label={`Remove ${s.account} split`}
                            onClick={() => { removeRecurringSplit(t.id, i); toast.success('Split removed', { description: s.account }); }}
                            className="text-muted-foreground hover:text-destructive ml-0.5"
                          >
                            <Icon name="trash" size={14} />
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}

            <div className="mt-2 flex items-center justify-between px-1 text-xs">
              <span className="text-muted-foreground">Total</span>
              <span className={cn('font-mono font-medium tabular-nums', totalPct === 100 ? 'text-success' : 'text-destructive')}>
                {totalPct}%
              </span>
            </div>
          </>
        )}
      </div>

      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit template</DialogTitle>
            <DialogDescription>{t.name}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>Name</Label>
              <Input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} autoFocus />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Amount</Label>
                <Input type="number" inputMode="decimal" value={draft.amount} placeholder={t.varies ? 'Varies' : '0.00'} onChange={(e) => setDraft({ ...draft, amount: e.target.value })} />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Day of month</Label>
                <Input type="number" inputMode="numeric" min={1} max={31} value={draft.dayOfMonth} onChange={(e) => setDraft({ ...draft, dayOfMonth: e.target.value })} />
              </div>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Frequency</Label>
              <Select value={draft.frequency} onValueChange={(v) => setDraft({ ...draft, frequency: v })}>
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {FREQUENCIES.map((f) => <SelectItem key={f} value={f}>{f}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="flex items-center justify-between">
              <Label htmlFor="rt-autopost">Auto-post</Label>
              <Switch id="rt-autopost" checked={draft.autoPost} onCheckedChange={(v) => setDraft({ ...draft, autoPost: v })} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitEdit}>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={splitOpen} onOpenChange={setSplitOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add split</DialogTitle>
            <DialogDescription>Direct a share of {t.name} to another account.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>Account</Label>
              <Input value={splitDraft.account} onChange={(e) => setSplitDraft({ ...splitDraft, account: e.target.value })} placeholder="e.g. Marcus Savings" autoFocus />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Percent</Label>
              <Input type="number" inputMode="numeric" min={0} max={100} value={splitDraft.pct} onChange={(e) => setSplitDraft({ ...splitDraft, pct: e.target.value })} placeholder="0" />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitSplit}>Add</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
