'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Money, Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { RowActions } from '@/components/RowActions';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import type { ScheduledTemplate } from '@/lib/store';
import { mutate } from '@/lib/api-client';
import { cn } from '@/lib/utils';

const WEEKDAYS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const WEEKDAY_LABELS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const TYPES = ['reminder', 'expense', 'income', 'transfer'];
const FREQUENCIES = ['daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'];

interface DraftForm {
  id: string;
  name: string;
  amount: string;
  type: string;
  frequency: string;
  dayOfMonth: string;
  weekDay: string;
  account: string;
  from: string;
  autoPost: boolean;
  color: string;
}

const EMPTY_DRAFT: DraftForm = {
  id: '', name: '', amount: '', type: 'reminder', frequency: 'monthly',
  dayOfMonth: '1', weekDay: '', account: '', from: '', autoPost: false, color: '#c96442',
};

function templateToDraft(t: ScheduledTemplate): DraftForm {
  return {
    id: t.id,
    name: t.name,
    amount: t.amount == null ? '' : String(t.amount),
    type: t.type,
    frequency: t.frequency,
    dayOfMonth: String(t.dayOfMonth || 1),
    weekDay: t.weekDay != null ? String(t.weekDay) : '',
    account: t.account ?? '',
    from: t.from ?? '',
    autoPost: !!t.autoPost,
    color: t.color ?? '#c96442',
  };
}

export default function ScheduledPage() {
  const [view, setView] = useState({ y: 2026, m: 5 });
  const [selectedDay, setSelectedDay] = useState<number | null>(null);
  const { activeId } = useLedger();
  const scheduled = useFinanceStore((s) => s.scheduled);
  const createScheduled = useFinanceStore((s) => s.createScheduled);
  const updateScheduled = useFinanceStore((s) => s.updateScheduled);
  const deleteScheduled = useFinanceStore((s) => s.deleteScheduled);

  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<DraftForm>(EMPTY_DRAFT);
  const [isNew, setIsNew] = useState(true);

  const openCreate = () => { setIsNew(true); setDraft(EMPTY_DRAFT); setOpen(true); };

  const openEdit = (t: ScheduledTemplate) => {
    setIsNew(false);
    setDraft(templateToDraft(t));
    setOpen(true);
  };

  const submit = () => {
    const name = draft.name.trim();
    if (!name) return void toast.error('Enter a name');
    const amount = draft.amount.trim() === '' ? null : Number(draft.amount);
    const dayOfMonth = Number(draft.dayOfMonth) || 1;
    const weekDay = draft.weekDay !== '' ? Number(draft.weekDay) : undefined;
    const type = draft.type;
    if (isNew) {
      createScheduled({
        name,
        type,
        amount,
        frequency: draft.frequency,
        dayOfMonth,
        weekDay,
        account: type === 'reminder' ? undefined : draft.account.trim(),
        from: type === 'transfer' ? draft.from.trim() || undefined : undefined,
        autoPost: draft.autoPost,
        color: draft.color,
        ledgerId: activeId,
      });
      toast.success('Scheduled item added', { description: name });
    } else {
      updateScheduled(draft.id, {
        name,
        amount,
        frequency: draft.frequency,
        dayOfMonth,
        weekDay,
        autoPost: draft.autoPost ? 1 : 0,
        color: draft.color,
      });
      toast.success('Scheduled item updated', { description: name });
    }
    setOpen(false);
  };

  const [posting, setPosting] = useState<string | null>(null);
  const postNow = async (templateId: string, name: string) => {
    setPosting(templateId);
    try {
      const state = await mutate('postScheduled', { templateId });
      useFinanceStore.setState(state);
      toast.success(`Posted "${name}"`, { description: 'Added to transactions.' });
    } catch (err) {
      toast.error((err as Error).message || 'Could not post');
    } finally {
      setPosting(null);
    }
  };

  const totalOutgoing = scheduled
    .filter((t) => t.type !== 'income' && t.amount != null)
    .reduce((s, t) => s + (t.amount ?? 0), 0);
  const totalIncoming = scheduled
    .filter((t) => t.type === 'income' && t.amount != null)
    .reduce((s, t) => s + (t.amount ?? 0), 0);
  const netTotal = totalIncoming + totalOutgoing;

  const firstDow = new Date(view.y, view.m, 1).getDay();
  const daysInMonth = new Date(view.y, view.m + 1, 0).getDate();

  const dotsByDay = buildDotsByDay(scheduled, view.y, view.m, daysInMonth);

  const shift = (delta: number) =>
    setView((v) => {
      const d = new Date(v.y, v.m + delta, 1);
      setSelectedDay(null);
      return { y: d.getFullYear(), m: d.getMonth() };
    });

  const monthItems = daysForMonth(scheduled, view.y, view.m);
  const onSelectedDay = selectedDay != null ? monthItems.filter((i) => i.day === selectedDay) : [];
  const afterSelectedDay = selectedDay != null ? monthItems.filter((i) => i.day > selectedDay) : [];

  return (
    <MobilePage
      header={<ScreenHeader title="Scheduled" trailing={<IconButton icon="plus" aria-label="New scheduled item" onClick={openCreate} />} />}
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Upcoming"
          value={<Money value={netTotal} mono={false} className="font-serif" />}
          sublabel={
            <span className="text-success">
              +<Money value={totalIncoming} /> incoming
            </span>
          }
        />
      </div>

      <div className="md:grid md:grid-cols-[1.6fr_1fr] md:items-start md:gap-6 md:px-8">
      <div className="px-5 pb-5 md:px-0">
        <div className="bg-card border-border rounded-xl border p-4 md:p-5">
          <div className="mb-3 flex items-center justify-between">
            <div className="font-serif text-base italic">
              {MONTH_NAMES[view.m]} {view.y}
            </div>
            <div className="flex items-center gap-1">
              <button
                type="button" aria-label="Previous month" onClick={() => shift(-1)}
                className="border-border text-muted-foreground hover:text-foreground flex size-7 cursor-pointer items-center justify-center rounded-md border"
              >
                <Icon name="chev-l" size={14} />
              </button>
              <button
                type="button" aria-label="Next month" onClick={() => shift(1)}
                className="border-border text-muted-foreground hover:text-foreground flex size-7 cursor-pointer items-center justify-center rounded-md border"
              >
                <Icon name="chev" size={14} />
              </button>
            </div>
          </div>
          <div className="text-muted-foreground mb-1 grid grid-cols-7 text-center font-mono text-[10px]">
            {WEEKDAYS.map((d, i) => <div key={i}>{d}</div>)}
          </div>
          <div className="grid grid-cols-7 gap-y-1">
            {Array.from({ length: firstDow }).map((_, i) => <div key={`b${i}`} />)}
            {Array.from({ length: daysInMonth }).map((_, i) => {
              const day = i + 1;
              const dots = dotsByDay.get(day);
              const isSelected = day === selectedDay;
              return (
                <button
                  key={day}
                  type="button" aria-label={`${MONTH_NAMES[view.m]} ${day}`} aria-pressed={isSelected}
                  onClick={() => setSelectedDay((prev) => (prev === day ? null : day))}
                  className={cn(
                    'flex cursor-pointer flex-col items-center gap-1 rounded-md py-1 md:py-2.5',
                    isSelected ? 'bg-primary text-primary-foreground' : 'hover:bg-secondary',
                  )}
                >
                  <span className="text-[13px] tabular-nums">{day}</span>
                  <span className="flex h-1.5 gap-0.5">
                    {dots?.slice(0, 3).map((d, j) => (
                      <span key={j} className="size-1.5 rounded-full" style={{ background: d.color }} />
                    ))}
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <div className="flex flex-col gap-2.5 px-5 pb-[120px] md:px-0 md:pb-12">
        <div className="flex items-center justify-between px-1">
          <div className="text-muted-foreground font-mono text-[10px] tracking-wider uppercase">
            {selectedDay != null ? `${MONTH_NAMES[view.m]} ${selectedDay}` : 'Upcoming'}
          </div>
          <Button variant="outline" size="sm" className="h-7" onClick={openCreate}>
            <Icon name="plus" size={13} />New
          </Button>
        </div>
        {selectedDay != null ? (
          <>
            {onSelectedDay.length > 0 ? (
              onSelectedDay.map((item) => (
                <ScheduledCard
                  key={item.id}
                  item={item}
                  onEdit={openEdit}
                  onDelete={() => { deleteScheduled(item.id); toast.success('Scheduled item deleted', { description: item.name }); }}
                  onPost={postNow}
                  posting={posting === item.id}
                />
              ))
            ) : (
              <div className="text-muted-foreground rounded-xl border border-dashed border-border py-4 text-center text-[12px]">
                Nothing on this day
              </div>
            )}
            {afterSelectedDay.length > 0 && (
              <>
                <div className="text-muted-foreground mt-3 px-1 font-mono text-[10px] tracking-wider uppercase">Upcoming</div>
                {afterSelectedDay.map((item) => (
                  <ScheduledCard
                    key={item.id}
                    item={item}
                    onEdit={openEdit}
                    onDelete={() => { deleteScheduled(item.id); toast.success('Scheduled item deleted', { description: item.name }); }}
                    onPost={postNow}
                    posting={posting === item.id}
                  />
                ))}
              </>
            )}
          </>
        ) : (
          [...scheduled]
            .sort((a, b) => (a.dayOfMonth || 0) - (b.dayOfMonth || 0))
            .map((item) => (
              <ScheduledCard
                key={item.id}
                item={{
                  id: item.id,
                  name: item.name,
                  amount: item.amount,
                  type: item.type,
                  frequency: item.frequency,
                  day: item.dayOfMonth || 0,
                  dayOfMonth: item.dayOfMonth || 0,
                  weekDay: item.weekDay,
                  account: item.account ?? '',
                  from: item.from,
                  autoPost: item.autoPost,
                  color: item.color ?? 'var(--primary)',
                }}
                onEdit={openEdit}
                onDelete={() => { deleteScheduled(item.id); toast.success('Scheduled item deleted', { description: item.name }); }}
                onPost={postNow}
                posting={posting === item.id}
              />
            ))
        )}
      </div>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{isNew ? 'New scheduled item' : 'Edit scheduled item'}</DialogTitle>
            <DialogDescription>A scheduled bill, income, transfer or calendar reminder.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>Name</Label>
              <Input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="e.g. Rent" autoFocus />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Amount</Label>
                <Input type="number" inputMode="decimal" value={draft.amount} onChange={(e) => setDraft({ ...draft, amount: e.target.value })} placeholder="0.00" />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Type</Label>
                <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v })}>
                  <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {TYPES.map((t) => <SelectItem key={t} value={t}>{t}</SelectItem>)}
                  </SelectContent>
                </Select>
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
              {(draft.frequency === 'weekly' || draft.frequency === 'biweekly') ? (
                <div className="flex flex-col gap-1.5">
                  <Label>Day of week</Label>
                  <Select value={draft.weekDay} onValueChange={(v) => setDraft({ ...draft, weekDay: v })}>
                    <SelectTrigger className="w-full"><SelectValue placeholder="Select" /></SelectTrigger>
                    <SelectContent>
                      {WEEKDAY_LABELS.map((l, i) => <SelectItem key={i} value={String(i)}>{l}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              ) : (
                <div className="flex flex-col gap-1.5">
                  <Label>Day of month</Label>
                  <Input type="number" inputMode="numeric" min={1} max={31} value={draft.dayOfMonth} onChange={(e) => setDraft({ ...draft, dayOfMonth: e.target.value })} />
                </div>
              )}
            </div>
            {draft.type === 'transfer' ? (
              <>
                <div className="flex flex-col gap-1.5">
                  <Label>To account</Label>
                  <Input value={draft.account} onChange={(e) => setDraft({ ...draft, account: e.target.value })} placeholder="e.g. Marcus Savings" />
                </div>
                <div className="flex flex-col gap-1.5">
                  <Label>From account</Label>
                  <Input value={draft.from} onChange={(e) => setDraft({ ...draft, from: e.target.value })} placeholder="e.g. Chase Checking" />
                </div>
              </>
            ) : draft.type !== 'reminder' ? (
              <div className="flex flex-col gap-1.5">
                <Label>Account</Label>
                <Input value={draft.account} onChange={(e) => setDraft({ ...draft, account: e.target.value })} placeholder="e.g. Amex Gold" />
              </div>
            ) : null}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Label htmlFor="rt-color">Color</Label>
                <input id="rt-color" type="color" value={draft.color} onChange={(e) => setDraft({ ...draft, color: e.target.value })} className="border-border size-9 cursor-pointer rounded-md border bg-transparent" />
              </div>
              {draft.type !== 'reminder' && (
                <div className="flex items-center gap-2">
                  <Label htmlFor="rt-autopost">Auto-post</Label>
                  <Switch id="rt-autopost" checked={draft.autoPost} onCheckedChange={(v) => setDraft({ ...draft, autoPost: v })} />
                </div>
              )}
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submit}>{isNew ? 'Add' : 'Save'}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}

interface CalendarItem {
  id: string;
  name: string;
  amount: number | null;
  type: string;
  frequency: string;
  day: number;
  dayOfMonth: number;
  weekDay?: number;
  account: string;
  from?: string;
  autoPost: number;
  color: string;
}

function daysForMonth(items: ScheduledTemplate[], viewYear: number, viewMonth: number): CalendarItem[] {
  const result: CalendarItem[] = [];
  const daysInMonth = new Date(viewYear, viewMonth + 1, 0).getDate();
  for (const it of items) {
    const base = {
      id: it.id,
      name: it.name,
      amount: it.amount,
      type: it.type,
      frequency: it.frequency,
      dayOfMonth: it.dayOfMonth || 0,
      weekDay: it.weekDay,
      account: it.account ?? '',
      from: it.from,
      autoPost: it.autoPost,
      color: it.color ?? 'var(--primary)',
    };
    if (it.frequency === 'daily') {
      for (let d = 1; d <= daysInMonth; d++) {
        result.push({ ...base, day: d });
      }
    } else if (it.frequency === 'weekly' && it.weekDay != null) {
      const d = new Date(viewYear, viewMonth, 1);
      while (d.getDay() !== it.weekDay) d.setDate(d.getDate() + 1);
      while (d.getMonth() === viewMonth) {
        result.push({ ...base, day: d.getDate() });
        d.setDate(d.getDate() + 7);
      }
    } else if (it.frequency === 'biweekly' && it.weekDay != null) {
      const d = new Date(viewYear, viewMonth, 1);
      while (d.getDay() !== it.weekDay) d.setDate(d.getDate() + 1);
      const targetWeeks = [it.dayOfMonth || 1, (it.dayOfMonth || 1) + 2];
      while (d.getMonth() === viewMonth) {
        const currentWeek = Math.ceil(d.getDate() / 7);
        if (targetWeeks.includes(currentWeek)) {
          result.push({ ...base, day: d.getDate() });
        }
        d.setDate(d.getDate() + 14);
      }
    } else if (it.dayOfMonth >= 1 && it.dayOfMonth <= daysInMonth) {
      result.push({ ...base, day: it.dayOfMonth });
    }
  }
  return result;
}

function buildDotsByDay(items: ScheduledTemplate[], viewYear: number, viewMonth: number, daysInMonth: number) {
  const map = new Map<number, { color: string }[]>();
  for (const it of items) {
    const color = it.color ?? 'var(--primary)';
    if (it.frequency === 'daily') {
      for (let d = 1; d <= daysInMonth; d++) {
        const arr = map.get(d) ?? [];
        arr.push({ color });
        map.set(d, arr);
      }
    } else if (it.frequency === 'weekly' && it.weekDay != null) {
      const d = new Date(viewYear, viewMonth, 1);
      while (d.getDay() !== it.weekDay) d.setDate(d.getDate() + 1);
      while (d.getMonth() === viewMonth) {
        const arr = map.get(d.getDate()) ?? [];
        arr.push({ color });
        map.set(d.getDate(), arr);
        d.setDate(d.getDate() + 7);
      }
    } else if (it.frequency === 'biweekly' && it.weekDay != null) {
      const d = new Date(viewYear, viewMonth, 1);
      while (d.getDay() !== it.weekDay) d.setDate(d.getDate() + 1);
      const targetWeeks = [it.dayOfMonth || 1, (it.dayOfMonth || 1) + 2];
      while (d.getMonth() === viewMonth) {
        const currentWeek = Math.ceil(d.getDate() / 7);
        if (targetWeeks.includes(currentWeek)) {
          const arr = map.get(d.getDate()) ?? [];
          arr.push({ color });
          map.set(d.getDate(), arr);
        }
        d.setDate(d.getDate() + 14);
      }
    } else if (it.dayOfMonth >= 1 && it.dayOfMonth <= daysInMonth) {
      const arr = map.get(it.dayOfMonth) ?? [];
      arr.push({ color });
      map.set(it.dayOfMonth, arr);
    }
  }
  return map;
}

function ScheduledCard({ item, onEdit, onDelete, onPost, posting }: {
  item: CalendarItem;
  onEdit: (t: ScheduledTemplate) => void;
  onDelete: () => void;
  onPost: (id: string, name: string) => void;
  posting: boolean;
}) {
  const scheduled = useFinanceStore((s) => s.scheduled);
  const isPostable = item.type !== 'reminder' && item.amount != null;
  return (
    <div className="bg-card border-border flex items-center gap-3.5 rounded-xl border p-3.5">
      <div className="w-11 shrink-0 text-center">
        <div className="text-muted-foreground font-mono text-[9px] tracking-wide uppercase">{item.frequency}</div>
        <div className="mt-0.5 font-serif text-[22px] leading-none -tracking-[0.4px]">{item.day}</div>
      </div>
      <div className="min-w-0 flex-1">
        <div className="text-sm font-medium">{item.name}</div>
        <div className="text-muted-foreground mt-0.5 flex items-center gap-1.5 text-[11px]">
          <span className="size-1.5 rounded-full" style={{ background: item.color }} />
          {item.type}
          {item.account ? <> · {item.account}</> : null}
          {item.autoPost ? <span className="rounded bg-secondary px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px] text-secondary-foreground">AUTO</span> : null}
        </div>
      </div>
      <Money
        value={item.amount ?? 0}
        className={cn('text-sm font-medium', (item.amount ?? 0) > 0 ? 'text-success' : 'text-foreground')}
      />
      <div className="flex items-center gap-0.5">
        {isPostable && (
          <Button variant="ghost" size="icon" className="size-8" onClick={() => onPost(item.id, item.name)} disabled={posting} aria-label={`Post ${item.name}`}>
            <Icon name="plus" size={14} />
          </Button>
        )}
        <RowActions
          onEdit={() => {
            const t = scheduled.find((r) => r.id === item.id);
            if (t) onEdit(t);
          }}
          onDelete={onDelete}
          confirmTitle={`Delete ${item.name}?`}
          confirmDescription="This removes the scheduled item from your calendar."
        />
      </div>
    </div>
  );
}
