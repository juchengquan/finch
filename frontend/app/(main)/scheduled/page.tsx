'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Money, Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { SCHEDULED_ITEMS } from '@/lib/data';
import { ScheduledItem } from '@/components/ScheduledItem';
import { RowActions } from '@/components/RowActions';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

export default function ScheduledPage() {
  const [view, setView] = useState({ y: 2026, m: 5 }); // June 2026
  const [selectedDay, setSelectedDay] = useState<number | null>(null);
  const { activeId } = useLedger();
  const storeItems = useFinanceStore((s) => s.scheduledItems);
  const createScheduledItem = useFinanceStore((s) => s.createScheduledItem);
  const updateScheduledItem = useFinanceStore((s) => s.updateScheduledItem);
  const deleteScheduledItem = useFinanceStore((s) => s.deleteScheduledItem);

  // Projected scheduled items for the active ledger; static data as SSR fallback.
  const projected = storeItems.filter((i) => i.ledgerId === activeId).map((i) => ({ ...i, color: i.color ?? 'var(--primary)' }));
  const items = projected.length ? projected : SCHEDULED_ITEMS;
  const editable = projected.length > 0;

  const EMPTY = { id: '', label: '', amount: '', day: '1', month: MONTHS[view.m], type: 'Bill', color: '#c96442' };
  const [draft, setDraft] = useState<typeof EMPTY>(EMPTY);
  const [open, setOpen] = useState(false);
  const [isNew, setIsNew] = useState(true);

  const openCreate = () => { setIsNew(true); setDraft({ ...EMPTY, month: MONTHS[view.m] }); setOpen(true); };
  const openEdit = (it: { id?: string; label: string; amount: number; day: number; month: string; type: string; color: string }) => {
    setIsNew(false);
    setDraft({ id: it.id ?? '', label: it.label, amount: String(it.amount), day: String(it.day), month: it.month, type: it.type, color: it.color.startsWith('#') ? it.color : '#c96442' });
    setOpen(true);
  };
  const submit = () => {
    const label = draft.label.trim();
    if (!label) return void toast.error('Enter a label');
    const fields = { label, amount: Number(draft.amount) || 0, day: Number(draft.day) || 1, month: draft.month, type: draft.type, color: draft.color };
    if (isNew) {
      createScheduledItem({ ...fields, ledgerId: activeId });
      toast.success('Scheduled item added', { description: label });
    } else {
      updateScheduledItem(draft.id, fields);
      toast.success('Scheduled item updated', { description: label });
    }
    setOpen(false);
  };

  const totalOutgoing = items.filter((i) => i.amount < 0).reduce((s, i) => s + i.amount, 0);
  const totalIncoming = items.filter((i) => i.amount > 0).reduce((s, i) => s + i.amount, 0);
  const netTotal = totalIncoming + totalOutgoing;

  const firstDow = new Date(view.y, view.m, 1).getDay();
  const daysInMonth = new Date(view.y, view.m + 1, 0).getDate();

  const dotsByDay = new Map<number, string[]>();
  for (const it of items) {
    if (MONTHS.indexOf(it.month) !== view.m) continue;
    const arr = dotsByDay.get(it.day) ?? [];
    arr.push(it.color);
    dotsByDay.set(it.day, arr);
  }

  const shift = (delta: number) =>
    setView((v) => {
      const d = new Date(v.y, v.m + delta, 1);
      setSelectedDay(null);
      return { y: d.getFullYear(), m: d.getMonth() };
    });

  // Items scoped to the currently-viewed month, sorted by day. When a day is
  // selected we split into "on that day" + "after that day in the same month";
  // otherwise the side panel shows the full month's list.
  const monthItems = [...items]
    .filter((i) => MONTHS.indexOf(i.month) === view.m)
    .sort((a, b) => a.day - b.day);
  const onSelectedDay = selectedDay != null ? monthItems.filter((i) => i.day === selectedDay) : [];
  const afterSelectedDay = selectedDay != null ? monthItems.filter((i) => i.day > selectedDay) : [];

  return (
    <MobilePage
      header={<ScreenHeader title="Scheduled" trailing={<IconButton icon="plus" aria-label="New scheduled item" onClick={openCreate} />} />}
    >
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Next 30 days"
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
                type="button"
                aria-label="Previous month"
                onClick={() => shift(-1)}
                className="border-border text-muted-foreground hover:text-foreground flex size-7 cursor-pointer items-center justify-center rounded-md border"
              >
                <Icon name="chev-l" size={14} />
              </button>
              <button
                type="button"
                aria-label="Next month"
                onClick={() => shift(1)}
                className="border-border text-muted-foreground hover:text-foreground flex size-7 cursor-pointer items-center justify-center rounded-md border"
              >
                <Icon name="chev" size={14} />
              </button>
            </div>
          </div>
          <div className="text-muted-foreground mb-1 grid grid-cols-7 text-center font-mono text-[10px]">
            {WEEKDAYS.map((d, i) => (
              <div key={i}>{d}</div>
            ))}
          </div>
          <div className="grid grid-cols-7 gap-y-1">
            {Array.from({ length: firstDow }).map((_, i) => (
              <div key={`b${i}`} />
            ))}
            {Array.from({ length: daysInMonth }).map((_, i) => {
              const day = i + 1;
              const dots = dotsByDay.get(day);
              const isSelected = day === selectedDay;
              return (
                <button
                  key={day}
                  type="button"
                  aria-label={`${MONTH_NAMES[view.m]} ${day}`}
                  aria-pressed={isSelected}
                  onClick={() => setSelectedDay((prev) => (prev === day ? null : day))}
                  className={cn(
                    'flex cursor-pointer flex-col items-center gap-1 rounded-md py-1 md:py-2.5',
                    isSelected ? 'bg-primary text-primary-foreground' : 'hover:bg-secondary',
                  )}
                >
                  <span className="text-[13px] tabular-nums">{day}</span>
                  <span className="flex h-1.5 gap-0.5">
                    {dots?.slice(0, 3).map((c, j) => (
                      <span key={j} className="size-1.5 rounded-full" style={{ background: c }} />
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
              onSelectedDay.map((item, i) => {
                const id = (item as { id?: string }).id;
                return (
                  <ScheduledItem
                    key={id ?? `sel-${i}`}
                    item={item}
                    actions={editable && id ? (
                      <RowActions
                        onEdit={() => openEdit(item)}
                        onDelete={() => { deleteScheduledItem(id); toast.success('Scheduled item deleted', { description: item.label }); }}
                        confirmTitle={`Delete ${item.label}?`}
                        confirmDescription="This removes the scheduled item from your calendar."
                      />
                    ) : undefined}
                  />
                );
              })
            ) : (
              <div className="text-muted-foreground rounded-xl border border-dashed border-border py-4 text-center text-[12px]">
                Nothing scheduled on this day
              </div>
            )}
            {afterSelectedDay.length > 0 && (
              <>
                <div className="text-muted-foreground mt-3 px-1 font-mono text-[10px] tracking-wider uppercase">
                  Upcoming
                </div>
                {afterSelectedDay.map((item, i) => {
                  const id = (item as { id?: string }).id;
                  return (
                    <ScheduledItem
                      key={id ?? `up-${i}`}
                      item={item}
                      actions={editable && id ? (
                        <RowActions
                          onEdit={() => openEdit(item)}
                          onDelete={() => { deleteScheduledItem(id); toast.success('Scheduled item deleted', { description: item.label }); }}
                          confirmTitle={`Delete ${item.label}?`}
                          confirmDescription="This removes the scheduled item from your calendar."
                        />
                      ) : undefined}
                    />
                  );
                })}
              </>
            )}
          </>
        ) : (
          items.map((item, i) => {
            const id = (item as { id?: string }).id;
            return (
              <ScheduledItem
                key={id ?? i}
                item={item}
                actions={editable && id ? (
                  <RowActions
                    onEdit={() => openEdit(item)}
                    onDelete={() => { deleteScheduledItem(id); toast.success('Scheduled item deleted', { description: item.label }); }}
                    confirmTitle={`Delete ${item.label}?`}
                    confirmDescription="This removes the scheduled item from your calendar."
                  />
                ) : undefined}
              />
            );
          })
        )}
      </div>
      </div>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{isNew ? 'New scheduled item' : 'Edit scheduled item'}</DialogTitle>
            <DialogDescription>A recurring bill, subscription or payday on the calendar.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>Label</Label>
              <Input value={draft.label} onChange={(e) => setDraft({ ...draft, label: e.target.value })} placeholder="e.g. Rent" autoFocus />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Amount</Label>
                <Input type="number" inputMode="decimal" value={draft.amount} onChange={(e) => setDraft({ ...draft, amount: e.target.value })} placeholder="-0.00" />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Day</Label>
                <Input type="number" inputMode="numeric" min={1} max={31} value={draft.day} onChange={(e) => setDraft({ ...draft, day: e.target.value })} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Month</Label>
                <Select value={draft.month} onValueChange={(v) => setDraft({ ...draft, month: v })}>
                  <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {MONTHS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Type</Label>
                <Input value={draft.type} onChange={(e) => setDraft({ ...draft, type: e.target.value })} placeholder="Bill" />
              </div>
            </div>
            <div className="flex items-center justify-between">
              <Label htmlFor="sch-color">Color</Label>
              <input id="sch-color" type="color" value={draft.color} onChange={(e) => setDraft({ ...draft, color: e.target.value })} className="border-border size-9 cursor-pointer rounded-md border bg-transparent" />
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
