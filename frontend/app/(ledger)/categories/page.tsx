'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
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
import { useLedger } from '@/components/ledger-provider';
import { RowActions } from '@/components/RowActions';
import { useFinanceStore } from '@/lib/store';
import { MOCK } from '@/lib/data';
import { cn } from '@/lib/utils';

const TYPES = ['expense', 'income', 'transfer'] as const;
const ICON_CHOICES = ['fork', 'home', 'car', 'bag', 'film', 'heart', 'sync', 'tag', 'coins', 'wallet', 'chart', 'doc'];
const HUE_CHOICES = [12, 40, 90, 160, 200, 220, 280, 320];

function IconPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {ICON_CHOICES.map((ic) => (
        <button
          key={ic}
          type="button"
          aria-label={ic}
          aria-pressed={value === ic}
          onClick={() => onChange(ic)}
          className={cn(
            'flex size-9 items-center justify-center rounded-lg border transition-colors',
            value === ic ? 'border-foreground bg-secondary' : 'border-border text-muted-foreground hover:text-foreground',
          )}
        >
          <Icon name={ic} size={16} />
        </button>
      ))}
    </div>
  );
}

function HuePicker({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {HUE_CHOICES.map((h) => (
        <button
          key={h}
          type="button"
          aria-label={`hue ${h}`}
          aria-pressed={value === h}
          onClick={() => onChange(h)}
          className={cn('size-7 rounded-full border-2 transition-transform', value === h ? 'border-foreground scale-110' : 'border-transparent')}
          style={{ background: `oklch(0.65 0.13 ${h})` }}
        />
      ))}
    </div>
  );
}

type CatEdit = { id: string; name: string; type: string; icon: string; hue: number };

export default function CategoriesPage() {
  const { active, activeId } = useLedger();
  const categories = useFinanceStore((s) => s.categories);
  const createCategory = useFinanceStore((s) => s.createCategory);
  const updateCategory = useFinanceStore((s) => s.updateCategory);
  const deleteCategory = useFinanceStore((s) => s.deleteCategory);

  const list = categories.filter((c) => c.ledgerId === activeId);
  const hueById = new Map(MOCK.categories.map((c) => [c.id, c.hue]));
  const hueOf = (c: (typeof list)[number]) => c.hue ?? hueById.get(c.id) ?? 220;

  const [name, setName] = useState('');
  const [type, setType] = useState<string>('expense');
  const [icon, setIcon] = useState('tag');
  const [hue, setHue] = useState(220);
  const [editing, setEditing] = useState<CatEdit | null>(null);

  const openEdit = (c: (typeof list)[number]) =>
    setEditing({ id: c.id, name: c.name, type: c.type, icon: c.icon ?? 'tag', hue: hueOf(c) });

  const submitCreate = () => {
    const n = name.trim();
    if (!n) {
      toast.error('Enter a category name');
      return;
    }
    createCategory({ name: n, type, icon, hue, ledgerId: activeId });
    toast.success('Category created', { description: n });
    setName('');
    setType('expense');
    setIcon('tag');
    setHue(220);
  };

  const submitEdit = () => {
    const n = editing?.name.trim();
    if (!editing || !n) {
      toast.error('Enter a category name');
      return;
    }
    updateCategory(editing.id, { name: n, type: editing.type, icon: editing.icon, hue: editing.hue });
    toast.success('Category updated', { description: n });
    setEditing(null);
  };

  const createDialog = (
    <Dialog>
      <DialogTrigger asChild>
        <IconButton icon="plus" aria-label="New category" />
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New category</DialogTitle>
          <DialogDescription>Add a category to {active.name}.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label>Name</Label>
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Travel"
              autoFocus
              onKeyDown={(e) => e.key === 'Enter' && submitCreate()}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Type</Label>
            <Select value={type} onValueChange={setType}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {TYPES.map((t) => (
                  <SelectItem key={t} value={t}>{t}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Icon</Label>
            <IconPicker value={icon} onChange={setIcon} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Color</Label>
            <HuePicker value={hue} onChange={setHue} />
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <DialogClose asChild>
            <Button onClick={submitCreate}>Create</Button>
          </DialogClose>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  return (
    <MobilePage header={<ScreenHeader title="Categories" trailing={createDialog} />}>
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-5">
          <SchemaChip label="categories" />
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {list.length} <span className="text-muted-foreground italic">categories</span>
          </div>
          <div className="text-secondary-foreground mt-1.5 text-[13px]">
            Tap a category to rename it. Transactions in {active.name} can be filed under any of these.
          </div>
        </div>

        {list.length === 0 && (
          <div className="text-muted-foreground rounded-[14px] border border-dashed py-10 text-center text-sm">
            No categories yet — use the + button to add one.
          </div>
        )}

        {list.map((c) => (
          <div
            key={c.id}
            className="border-border bg-card mb-2.5 flex w-full items-center gap-3 rounded-[14px] border p-4"
          >
            <button
              type="button"
              onClick={() => openEdit(c)}
              className="flex min-w-0 flex-1 items-center gap-3 text-left"
            >
              <div
                className="flex size-9 flex-shrink-0 items-center justify-center rounded-lg text-white"
                style={{ background: `oklch(0.65 0.13 ${hueOf(c)})` }}
              >
                <Icon name={c.icon ?? 'tag'} size={16} />
              </div>
              <div className="min-w-0 flex-1 text-sm font-medium">{c.name}</div>
            </button>
            <span className="bg-secondary text-secondary-foreground rounded px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px] uppercase">
              {c.type}
            </span>
            <RowActions
              onEdit={() => openEdit(c)}
              onDelete={() => { deleteCategory(c.id); toast.success('Category deleted', { description: c.name }); }}
              confirmTitle={`Delete ${c.name}?`}
              confirmDescription="Transactions in this category become uncategorized. This can't be undone."
            />
          </div>
        ))}
      </div>

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit category</DialogTitle>
            <DialogDescription>Update the name, type, icon and colour.</DialogDescription>
          </DialogHeader>
          {editing && (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Name</Label>
                <Input
                  value={editing.name}
                  onChange={(e) => setEditing((prev) => (prev ? { ...prev, name: e.target.value } : prev))}
                  autoFocus
                  onKeyDown={(e) => e.key === 'Enter' && submitEdit()}
                />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Type</Label>
                <Select value={editing.type} onValueChange={(v) => setEditing((prev) => (prev ? { ...prev, type: v } : prev))}>
                  <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {TYPES.map((t) => (
                      <SelectItem key={t} value={t}>{t}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Icon</Label>
                <IconPicker value={editing.icon} onChange={(v) => setEditing((prev) => (prev ? { ...prev, icon: v } : prev))} />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Color</Label>
                <HuePicker value={editing.hue} onChange={(v) => setEditing((prev) => (prev ? { ...prev, hue: v } : prev))} />
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
