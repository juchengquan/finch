'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Money, Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Switch } from '@/components/ui/switch';
import { Dialog, DialogClose, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { RowActions } from '@/components/RowActions';
import { StatusBadge } from '@/components/StatusBadge';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import type { ScheduledTemplate } from '@/lib/store';
import { parseInstallmentTotal } from '@/lib/installment';
import { cn } from '@/lib/utils';

const WEEKDAYS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const WEEKDAY_LABELS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const TYPES = ['expense', 'income', 'transfer'];
const FREQUENCIES = ['daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'];

interface DraftForm {
  id: string;
  name: string;
  description: string;
  amount: string;
  type: string;
  frequency: string;
  dayOfMonth: string;
  weekDay: string;
  accountId: string;
  account: string;
  fromAccountId: string;
  from: string;
  autoPost: boolean;
  color: string;
  category: string;
  startDate: string;
  endDate: string;
  maxExecutions: string;
  installmentTotal: string;
  isRecurring: boolean;
}

const EMPTY_DRAFT: DraftForm = {
  id: '', name: '', description: '', amount: '', type: 'expense', frequency: 'monthly',
  dayOfMonth: '1', weekDay: '', accountId: '', account: '', fromAccountId: '', from: '', autoPost: false, color: '#c96442',
  category: '', startDate: new Date().toISOString().slice(0, 16), endDate: '', maxExecutions: '', installmentTotal: '', isRecurring: true,
};

function templateToDraft(t: ScheduledTemplate): DraftForm {
  return {
    id: t.id,
    name: t.name,
    description: t.description ?? '',
    amount: t.amount == null ? '' : String(t.amount),
    type: t.type,
    frequency: t.frequency,
    dayOfMonth: String(t.dayOfMonth || 1),
    weekDay: t.weekDay != null ? String(t.weekDay) : '',
    accountId: t.accountId ?? '',
    account: t.account ?? '',
    fromAccountId: t.fromAccountId ?? '',
    from: t.from ?? '',
    autoPost: !!t.autoPost,
    color: t.color ?? '#c96442',
    category: t.category ?? '',
    startDate: t.startDate ?? new Date().toISOString().slice(0, 16),
    endDate: t.endDate ?? '',
    maxExecutions: t.maxExecutions != null ? String(t.maxExecutions) : '',
    installmentTotal: t.installmentTotal != null ? String(t.installmentTotal) : '',
    isRecurring: t.frequency !== 'once',
  };
}

export default function ScheduledPage() {
  const [view, setView] = useState({ y: 2026, m: 5 });
  const [selectedDay, setSelectedDay] = useState<number | null>(null);
  const { activeId } = useLedger();
  const scheduled = useFinanceStore((s) => s.scheduled);
  const allTxns = useFinanceStore((s) => s.transactions);
  const accounts = useFinanceStore((s) => s.accounts);
  const categories = useFinanceStore((s) => s.categories);
  const createScheduled = useFinanceStore((s) => s.createScheduled);
  const updateScheduled = useFinanceStore((s) => s.updateScheduled);
  const deleteScheduled = useFinanceStore((s) => s.deleteScheduled);

  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<DraftForm>(EMPTY_DRAFT);
  const [isNew, setIsNew] = useState(true);
  // Native currency of the picked account — a template's amount is denominated
  // in its account's currency (derived from the FK, not stored).
  const draftCurrency = accounts.find((a) => a.id === draft.accountId)?.currency ?? '';

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
    const frequency = draft.isRecurring ? draft.frequency : 'once';
    const category = draft.category || null;
    const startDate = draft.startDate || undefined;
    const endDate = draft.endDate || null;
    const maxExecutions = draft.maxExecutions ? Number(draft.maxExecutions) : null;
    let installmentTotal: number | null;
    try {
      installmentTotal = parseInstallmentTotal(draft.installmentTotal);
    } catch (err) {
      return void toast.error(err instanceof Error ? err.message : 'Invalid installment total');
    }
    const description = draft.description.trim() || null;
    if (isNew) {
      if (!draft.accountId) return void toast.error('Pick an account');
      if (type === 'transfer' && !draft.fromAccountId) return void toast.error('Pick a source account');
      const acctName = accounts.find((a) => a.id === draft.accountId)?.name ?? '';
      const fromName = accounts.find((a) => a.id === draft.fromAccountId)?.name;
      createScheduled({
        name,
        description,
        type,
        amount,
        frequency,
        dayOfMonth,
        weekDay,
        accountId: draft.accountId,
        account: acctName,
        fromAccountId: type === 'transfer' ? draft.fromAccountId : undefined,
        from: type === 'transfer' ? fromName : undefined,
        autoPost: draft.autoPost,
        color: draft.color,
        category,
        startDate,
        endDate,
        maxExecutions,
        installmentTotal,
        ledgerId: activeId,
      });
      toast.success('Scheduled item added', { description: name });
    } else {
      updateScheduled(draft.id, {
        name,
        description,
        amount,
        frequency,
        dayOfMonth,
        weekDay,
        autoPost: draft.autoPost ? 1 : 0,
        color: draft.color,
        category,
        endDate,
        maxExecutions,
        installmentTotal,
      });
      toast.success('Scheduled item updated', { description: name });
    }
    setOpen(false);
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

  const goTo = (y: number, m: number) => {
    setSelectedDay(null);
    setView({ y, m });
  };
  // A range centered on the current view year so the selected value is always present.
  const YEARS = Array.from({ length: 13 }, (_, i) => view.y - 6 + i);

  const monthItems = daysForMonth(scheduled, view.y, view.m);
  const onSelectedDay = selectedDay != null ? monthItems.filter((i) => i.day === selectedDay) : [];
  const afterSelectedDay = selectedDay != null ? monthItems.filter((i) => i.day > selectedDay) : [];

  // Status of an occurrence = the status of its auto-generated transaction
  // (linked by sourceTemplateId + date). Not-yet-generated → "upcoming".
  const pad = (n: number) => String(n).padStart(2, '0');
  const isoOf = (day: number) => `${view.y}-${pad(view.m + 1)}-${pad(day)}`;
  const occPending = new Map<string, boolean>();
  for (const t of allTxns) {
    if (t.sourceTemplateId) occPending.set(`${t.sourceTemplateId}|${t.date}`, !!t.pending);
  }
  const occStatus = (templateId: string, day: number): 'pending' | 'done' | 'upcoming' => {
    const v = occPending.get(`${templateId}|${isoOf(day)}`);
    return v === undefined ? 'upcoming' : v ? 'pending' : 'done';
  };

  return (
    <MobilePage
      header={<ScreenHeader title="Scheduled" trailing={<IconButton icon="plus" aria-label="New scheduled item" onClick={openCreate} />} />}
    >
      <div className="px-5 pb-[22px]">
        <div className="text-muted-foreground text-[10px] tracking-wider uppercase">Upcoming</div>
        <div className="mt-1.5 flex flex-wrap items-baseline gap-x-3 gap-y-1">
          <Money
            value={netTotal}
            mono={false}
            className="font-serif text-4xl leading-none font-normal -tracking-[1.5px] sm:text-5xl sm:-tracking-[2px]"
          />
          <span className="text-success text-xs whitespace-nowrap">
            + <Money value={totalIncoming} /> incoming
          </span>
        </div>
      </div>

      <div className="md:grid md:grid-cols-[1.6fr_1fr] md:items-start md:gap-6 md:px-8">
      <div className="px-5 pb-5 md:px-0">
        <div className="bg-card border-border rounded-xl border p-4 md:p-5">
          <div className="mb-3 flex items-center justify-between">
            <div className="-ml-1.5 flex items-center gap-0.5">
              <Select value={String(view.m)} onValueChange={(v) => goTo(view.y, Number(v))}>
                <SelectTrigger
                  size="sm"
                  aria-label="Month"
                  className="h-7 gap-1 border-0 bg-transparent px-1.5 font-serif text-base italic shadow-none focus-visible:ring-0"
                >
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {MONTH_NAMES.map((m, i) => (
                    <SelectItem key={i} value={String(i)}>{m}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <Select value={String(view.y)} onValueChange={(v) => goTo(Number(v), view.m)}>
                <SelectTrigger
                  size="sm"
                  aria-label="Year"
                  className="h-7 gap-1 border-0 bg-transparent px-1.5 font-serif text-base italic shadow-none focus-visible:ring-0"
                >
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {YEARS.map((y) => (
                    <SelectItem key={y} value={String(y)}>{y}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
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
                  <span className="text-[15px] tabular-nums">{day}</span>
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
                  status={occStatus(item.id, item.day)}
                  onEdit={openEdit}
                  onDelete={() => { deleteScheduled(item.id); toast.success('Scheduled item deleted', { description: item.name }); }}
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
                    status={occStatus(item.id, item.day)}
                    onEdit={openEdit}
                    onDelete={() => { deleteScheduled(item.id); toast.success('Scheduled item deleted', { description: item.name }); }}
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
                  category: item.category ?? null,
                  installmentTotal: item.installmentTotal ?? null,
                  installmentPaid: item.installmentPaid ?? 0,
                }}
                status={occStatus(item.id, item.dayOfMonth || 0)}
                onEdit={openEdit}
                onDelete={() => { deleteScheduled(item.id); toast.success('Scheduled item deleted', { description: item.name }); }}
              />
            ))
        )}
      </div>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{isNew ? 'New scheduled item' : 'Edit scheduled item'}</DialogTitle>
          </DialogHeader>
          <div className="flex flex-col gap-3 max-h-[60vh] overflow-y-auto pr-1">
            <div className="flex items-center gap-0.5 rounded-lg bg-secondary p-0.5">
              {TYPES.map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setDraft({ ...draft, type: t })}
                  className={cn(
                    'flex-1 rounded-md py-1.5 text-[13px] font-medium transition-colors capitalize',
                    draft.type === t ? 'bg-background text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground',
                  )}
                >
                  {t}
                </button>
              ))}
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Name</Label>
              <Input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="e.g. Rent" autoFocus />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Description <span className="text-muted-foreground font-normal">(optional)</span></Label>
              <Input value={draft.description} onChange={(e) => setDraft({ ...draft, description: e.target.value })} placeholder="Shown on each posted transaction — defaults to the name" />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Amount{draftCurrency ? <span className="text-muted-foreground font-normal"> · {draftCurrency}</span> : null}</Label>
              <Input type="number" inputMode="decimal" value={draft.amount} onChange={(e) => setDraft({ ...draft, amount: e.target.value })} placeholder="0.00" />
            </div>
            {draft.type === 'transfer' ? (
              <>
                <div className="flex flex-col gap-1.5">
                  <Label>To account</Label>
                  <Select value={draft.accountId} onValueChange={(v) => setDraft({ ...draft, accountId: v })}>
                    <SelectTrigger className="w-full"><SelectValue placeholder="Select account" /></SelectTrigger>
                    <SelectContent>
                      {accounts.filter(a => a.ledgerId === activeId).map((a) => <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="flex flex-col gap-1.5">
                  <Label>From account</Label>
                  <Select value={draft.fromAccountId} onValueChange={(v) => setDraft({ ...draft, fromAccountId: v })}>
                    <SelectTrigger className="w-full"><SelectValue placeholder="Select account" /></SelectTrigger>
                    <SelectContent>
                      {accounts.filter(a => a.ledgerId === activeId).map((a) => <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </>
            ) : (
              <div className="flex flex-col gap-1.5">
                <Label>Account</Label>
                <Select value={draft.accountId} onValueChange={(v) => setDraft({ ...draft, accountId: v })}>
                  <SelectTrigger className="w-full"><SelectValue placeholder="Select account" /></SelectTrigger>
                  <SelectContent>
                    {accounts.filter(a => a.ledgerId === activeId).map((a) => <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            )}
            <div className="flex flex-col gap-1.5">
              <Label>Category</Label>
              <Select value={draft.category} onValueChange={(v) => setDraft({ ...draft, category: v })}>
                <SelectTrigger className="w-full"><SelectValue placeholder="None" /></SelectTrigger>
                <SelectContent>
                  {categories.filter(c => c.type === 'expense' || c.type === 'income').map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Date</Label>
              <Input type="datetime-local" value={draft.startDate} onChange={(e) => setDraft({ ...draft, startDate: e.target.value })} />
            </div>
            <div className="flex items-center justify-between">
              <Label htmlFor="sch-recurring">Recurring</Label>
              <Switch id="sch-recurring" checked={draft.isRecurring} onCheckedChange={(v) => setDraft({ ...draft, isRecurring: v })} />
            </div>
            {draft.isRecurring && (
              <>
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
                <div className="grid grid-cols-2 gap-3">
                  <div className="flex flex-col gap-1.5">
                    <Label>Repeat</Label>
                    <Input type="number" inputMode="numeric" min={1} value={draft.maxExecutions} onChange={(e) => setDraft({ ...draft, maxExecutions: e.target.value })} placeholder="Infinite" />
                  </div>
                  <div className="flex flex-col gap-1.5">
                    <Label>Until date</Label>
                    <Input type="datetime-local" value={draft.endDate} onChange={(e) => setDraft({ ...draft, endDate: e.target.value })} />
                  </div>
                </div>
                <div className="flex flex-col gap-1.5">
                  <Label>Installment plan</Label>
                  <Input type="number" inputMode="numeric" min={1} value={draft.installmentTotal} onChange={(e) => setDraft({ ...draft, installmentTotal: e.target.value })} placeholder="e.g. 24 for a 24-month plan" />
                  <p className="text-muted-foreground text-[11px]">Stops auto-posting after this many payments and shows progress. Leave blank for an ordinary recurring expense.</p>
                </div>
              </>
            )}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Label htmlFor="rt-color">Color</Label>
                <input id="rt-color" type="color" value={draft.color} onChange={(e) => setDraft({ ...draft, color: e.target.value })} className="border-border size-9 cursor-pointer rounded-md border bg-transparent" />
              </div>
              {draft.type !== 'transfer' && (
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
  category?: string | null;
  installmentTotal?: number | null;
  installmentPaid?: number;
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
      frequency: it.frequency === 'once' ? 'once' : it.frequency,
      dayOfMonth: it.dayOfMonth || 0,
      weekDay: it.weekDay,
      account: it.account ?? '',
      from: it.from,
      autoPost: it.autoPost,
      color: it.color ?? 'var(--primary)',
      category: it.category ?? null,
      installmentTotal: it.installmentTotal ?? null,
      installmentPaid: it.installmentPaid ?? 0,
    };
    if (it.frequency === 'once') {
      if (it.startDate) {
        const d = new Date(it.startDate + 'T00:00');
        if (d.getFullYear() === viewYear && d.getMonth() === viewMonth) {
          result.push({ ...base, day: d.getDate() });
        }
      }
    } else if (it.frequency === 'daily') {
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
    if (it.frequency === 'once') {
      if (it.startDate) {
        const d = new Date(it.startDate + 'T00:00');
        if (d.getFullYear() === viewYear && d.getMonth() === viewMonth) {
          const arr = map.get(d.getDate()) ?? [];
          arr.push({ color });
          map.set(d.getDate(), arr);
        }
      }
    } else if (it.frequency === 'daily') {
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

function ScheduledCard({ item, status = 'upcoming', onEdit, onDelete }: {
  item: CalendarItem;
  status?: 'pending' | 'done' | 'upcoming';
  onEdit: (t: ScheduledTemplate) => void;
  onDelete: () => void;
}) {
  const scheduled = useFinanceStore((s) => s.scheduled);
  const categories = useFinanceStore((s) => s.categories);
  return (
    <div className="bg-card border-border flex items-center gap-3.5 rounded-xl border p-3.5">
      <div className="w-11 shrink-0 text-center">
        <div className="text-muted-foreground font-mono text-[9px] tracking-wide uppercase">{item.frequency === 'once' ? 'once' : item.frequency}</div>
        <div className="mt-0.5 font-serif text-[22px] leading-none -tracking-[0.4px]">{item.day}</div>
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium">{item.name}</span>
          <StatusBadge status={status} />
        </div>
        <div className="text-muted-foreground mt-0.5 flex items-center gap-1.5 text-[11px]">
          <span className="size-1.5 rounded-full" style={{ background: item.color }} />
          {item.type}
          {item.category ? <> · {categories.find(c => c.id === item.category)?.name ?? item.category}</> : null}
          {item.account ? <> · {item.account}</> : null}
          {item.autoPost ? <span className="rounded bg-secondary px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px] text-secondary-foreground">AUTO</span> : null}
          {item.installmentTotal != null && (
            <span
              className={cn(
                'rounded px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px]',
                (item.installmentPaid ?? 0) >= item.installmentTotal
                  ? 'bg-success/10 text-success'
                  : 'bg-secondary text-secondary-foreground',
              )}
            >
              {item.installmentPaid ?? 0}/{item.installmentTotal}
            </span>
          )}
        </div>
      </div>
      <Money
        value={item.amount ?? 0}
        className={cn('text-sm font-medium', (item.amount ?? 0) > 0 ? 'text-success' : 'text-foreground')}
      />
      <div className="flex items-center gap-0.5">
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
