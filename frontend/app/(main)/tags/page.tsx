'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { RowActions } from '@/components/RowActions';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import { tagHex, DEFAULT_TAG_HEX } from '@/lib/colors';
import { cn } from '@/lib/utils';

// Curated palette of tag colours, precomputed from the legacy hue list at the
// standard tag lightness/chroma so the picker keeps its palette feel.
const COLOR_CHOICES = [12, 40, 90, 160, 200, 220, 280, 320].map(tagHex);

function ColorPicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {COLOR_CHOICES.map((c) => (
        <button
          key={c}
          type="button"
          aria-label={`color ${c}`}
          aria-pressed={value === c}
          onClick={() => onChange(c)}
          className={cn('size-7 rounded-full border-2 transition-transform', value === c ? 'border-foreground scale-110' : 'border-transparent')}
          style={{ background: c }}
        />
      ))}
    </div>
  );
}

export default function TagsPage() {
  const { active, activeId } = useLedger();
  const tags = useFinanceStore((s) => s.tags);
  const createTag = useFinanceStore((s) => s.createTag);
  const updateTag = useFinanceStore((s) => s.updateTag);
  const deleteTag = useFinanceStore((s) => s.deleteTag);

  const list = tags.filter((t) => t.ledgerId === activeId);

  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState('');
  const [color, setColor] = useState(DEFAULT_TAG_HEX);
  const submitCreate = () => {
    const n = name.trim();
    if (!n) return void toast.error('Enter a tag name');
    createTag({ name: n, color, ledgerId: activeId });
    toast.success('Tag created', { description: n });
    setName('');
    setColor(DEFAULT_TAG_HEX);
    setCreateOpen(false);
  };

  const [editing, setEditing] = useState<{ id: string; name: string; color: string } | null>(null);
  const submitEdit = () => {
    if (!editing) return;
    const n = editing.name.trim();
    if (!n) return void toast.error('Enter a tag name');
    updateTag(editing.id, { name: n, color: editing.color });
    toast.success('Tag updated', { description: n });
    setEditing(null);
  };

  return (
    <MobilePage
      header={<ScreenHeader title="Tags" trailing={<IconButton icon="plus" aria-label="New tag" onClick={() => setCreateOpen(true)} />} />}
    >
      <div className="px-5 pb-[120px]">
        <div className="hidden items-center justify-end pt-2 pb-3 md:flex">
          <Button size="sm" variant="outline" onClick={() => setCreateOpen(true)}>
            <Icon name="plus" size={14} />
            New tag
          </Button>
        </div>
        <div className="px-1 pb-5">
          <SchemaChip label="tags" />
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {list.length} <span className="text-muted-foreground italic">tags</span>
          </div>
          <div className="text-secondary-foreground mt-1.5 text-[13px]">
            Labels you can attach to transactions in {active.name}.
          </div>
        </div>

        {list.length === 0 && (
          <div className="text-muted-foreground rounded-[14px] border border-dashed py-10 text-center text-sm">
            No tags yet — use the + button to add one.
          </div>
        )}

        {list.map((t) => (
          <div key={t.id} className="border-border bg-card mb-2.5 flex w-full items-center gap-3 rounded-[14px] border p-4">
            <button type="button" onClick={() => setEditing({ id: t.id, name: t.name, color: t.color ?? DEFAULT_TAG_HEX })} className="flex min-w-0 flex-1 items-center gap-3 text-left">
              <span className="size-4 shrink-0 rounded-full" style={{ background: t.color ?? DEFAULT_TAG_HEX }} />
              <div className="min-w-0 flex-1 text-sm font-medium">{t.name}</div>
            </button>
            <RowActions
              onEdit={() => setEditing({ id: t.id, name: t.name, color: t.color ?? DEFAULT_TAG_HEX })}
              onDelete={() => { deleteTag(t.id); toast.success('Tag deleted', { description: t.name }); }}
              confirmTitle={`Delete ${t.name}?`}
              confirmDescription="The tag is removed from every transaction it's on. This can't be undone."
            />
          </div>
        ))}
      </div>

      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>New tag</DialogTitle>
            <DialogDescription>Add a tag to {active.name}.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>Name</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Reimbursable" autoFocus onKeyDown={(e) => e.key === 'Enter' && submitCreate()} />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>Color</Label>
              <ColorPicker value={color} onChange={setColor} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitCreate}>Create</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit tag</DialogTitle>
            <DialogDescription>Update the name or colour.</DialogDescription>
          </DialogHeader>
          {editing && (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Name</Label>
                <Input value={editing.name} onChange={(e) => setEditing((p) => (p ? { ...p, name: e.target.value } : p))} autoFocus />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Color</Label>
                <ColorPicker value={editing.color} onChange={(v) => setEditing((p) => (p ? { ...p, color: v } : p))} />
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
