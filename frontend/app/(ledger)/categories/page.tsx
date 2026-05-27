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
import { useFinanceStore } from '@/lib/store';
import { MOCK } from '@/lib/data';

const TYPES = ['expense', 'income', 'transfer'] as const;

export default function CategoriesPage() {
  const { active, activeId } = useLedger();
  const categories = useFinanceStore((s) => s.categories);
  const createCategory = useFinanceStore((s) => s.createCategory);
  const renameCategory = useFinanceStore((s) => s.renameCategory);

  const list = categories.filter((c) => c.ledgerId === activeId);
  const hueById = new Map(MOCK.categories.map((c) => [c.id, c.hue]));

  const [name, setName] = useState('');
  const [type, setType] = useState<string>('expense');
  const [editing, setEditing] = useState<{ id: string; name: string } | null>(null);

  const submitCreate = () => {
    const n = name.trim();
    if (!n) {
      toast.error('Enter a category name');
      return;
    }
    createCategory({ name: n, type, ledgerId: activeId });
    toast.success('Category created', { description: n });
    setName('');
    setType('expense');
  };

  const submitRename = () => {
    const n = editing?.name.trim();
    if (!editing || !n) {
      toast.error('Enter a category name');
      return;
    }
    renameCategory(editing.id, n);
    toast.success('Category renamed', { description: n });
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
          <button
            key={c.id}
            type="button"
            onClick={() => setEditing({ id: c.id, name: c.name })}
            className="border-border bg-card mb-2.5 flex w-full items-center gap-3 rounded-[14px] border p-4 text-left"
          >
            <div
              className="flex size-9 flex-shrink-0 items-center justify-center rounded-lg text-white"
              style={{ background: `oklch(0.65 0.13 ${hueById.get(c.id) ?? 220})` }}
            >
              <Icon name={c.icon ?? 'tag'} size={16} />
            </div>
            <div className="min-w-0 flex-1 text-sm font-medium">{c.name}</div>
            <span className="bg-secondary text-secondary-foreground rounded px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px] uppercase">
              {c.type}
            </span>
            <Icon name="chev" size={12} className="text-muted-foreground shrink-0" />
          </button>
        ))}
      </div>

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rename category</DialogTitle>
            <DialogDescription>Update the category name.</DialogDescription>
          </DialogHeader>
          <Input
            value={editing?.name ?? ''}
            onChange={(e) => setEditing((prev) => (prev ? { ...prev, name: e.target.value } : prev))}
            autoFocus
            onKeyDown={(e) => e.key === 'Enter' && submitRename()}
          />
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitRename}>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
