'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
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

  const [query, setQuery] = useState('');
  const q = query.toLowerCase();
  const filteredList = q ? list.filter((t) => t.name.toLowerCase().includes(q)) : list;

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
      header={<ScreenHeader title="Tags" />}
    >
      <div className="px-5 pb-[120px]">
        {/* Search + Add row (visible on both mobile and desktop, Categories-style) */}
        <div className="mb-3.5 flex items-center gap-2">
          <div className="bg-secondary flex h-[38px] flex-1 items-center gap-2.5 rounded-[19px] px-3.5 text-[13px]">
            <Icon name="search" size={14} className="text-muted-foreground" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label="Search tags"
              placeholder="Search tags…"
              className="placeholder:text-muted-foreground focus-ring w-full bg-transparent outline-none"
            />
          </div>
          <Button
            onClick={() => setCreateOpen(true)}
            size="icon"
            className="rounded-full"
            aria-label="New tag"
            title="New tag"
          >
            <Icon name="plus" size={16} stroke={2} />
          </Button>
        </div>

        {list.length === 0 ? (
          <div className="text-muted-foreground rounded-[14px] border border-dashed py-10 text-center text-sm">
            No tags yet — tap + to add one.
          </div>
        ) : filteredList.length === 0 ? (
          <div className="text-muted-foreground py-8 text-center text-sm">No matches</div>
        ) : (
          <div className="border-border bg-card divide-border divide-y overflow-hidden rounded-[14px] border">
            {filteredList.map((t) => (
              <div
                key={t.id}
                className="flex items-center gap-3 px-4 py-3.5 transition-colors hover:bg-secondary/50"
              >
                <span
                  className="size-2.5 shrink-0 rounded-full"
                  style={{ background: t.color ?? DEFAULT_TAG_HEX }}
                />
                <div className="min-w-0 flex-1 text-sm font-medium">{t.name}</div>
                <RowActions
                  onEdit={() => setEditing({ id: t.id, name: t.name, color: t.color ?? DEFAULT_TAG_HEX })}
                  onDelete={() => { deleteTag(t.id); toast.success('Tag deleted', { description: t.name }); }}
                  confirmTitle={`Delete ${t.name}?`}
                  confirmDescription="The tag is removed from every transaction it's on. This can't be undone."
                />
              </div>
            ))}
          </div>
        )}
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
