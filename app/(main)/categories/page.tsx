'use client';

import { useMemo, useState } from 'react';
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
import { categoryHex, DEFAULT_CATEGORY_HEX } from '@/lib/colors';
import { buildCategoryTree, type CategoryRow } from '@/lib/db/queries/categories';
import { cn } from '@/lib/utils';

const TYPES = ['expense', 'income', 'transfer'] as const;
const ICON_CHOICES = ['fork', 'home', 'car', 'bag', 'film', 'heart', 'sync', 'tag', 'coins', 'wallet', 'chart', 'doc'];
// Curated palette of category colours, precomputed from the legacy hue list at
// the standard category lightness/chroma so the picker keeps its palette feel.
const COLOR_CHOICES = [12, 40, 90, 160, 200, 220, 280, 320].map(categoryHex);

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

type CatDraft = {
  id: string | null; // null = create
  name: string;
  type: string;
  icon: string;
  color: string;
  /** null = top-level; otherwise the id of a top-level row. */
  parentId: string | null;
};

const EMPTY_DRAFT: CatDraft = {
  id: null,
  name: '',
  type: 'expense',
  icon: 'tag',
  color: DEFAULT_CATEGORY_HEX,
  parentId: null,
};

export default function CategoriesPage() {
  const { active, activeId } = useLedger();
  const categories = useFinanceStore((s) => s.categories);
  const createCategory = useFinanceStore((s) => s.createCategory);
  const updateCategory = useFinanceStore((s) => s.updateCategory);
  const deleteCategory = useFinanceStore((s) => s.deleteCategory);

  const list = categories.filter((c) => c.ledgerId === activeId);
  const tree = useMemo(() => buildCategoryTree(list), [list]);
  const topLevel = useMemo(() => list.filter((c) => c.parentId == null), [list]);
  const colorOf = (c: CategoryRow) => c.color ?? DEFAULT_CATEGORY_HEX;

  const [draft, setDraft] = useState<CatDraft>(EMPTY_DRAFT);
  const [dialogOpen, setDialogOpen] = useState(false);

  const openCreateTop = () => {
    setDraft(EMPTY_DRAFT);
    setDialogOpen(true);
  };

  const openCreateChild = (parentId: string) => {
    const parent = list.find((c) => c.id === parentId);
    setDraft({
      ...EMPTY_DRAFT,
      parentId,
      type: parent?.type ?? 'expense',
      color: parent?.color ?? DEFAULT_CATEGORY_HEX,
    });
    setDialogOpen(true);
  };

  const openEdit = (c: CategoryRow) => {
    setDraft({
      id: c.id,
      name: c.name,
      type: c.type,
      icon: c.icon ?? 'tag',
      color: colorOf(c),
      parentId: c.parentId,
    });
    setDialogOpen(true);
  };

  const submit = () => {
    const n = draft.name.trim();
    if (!n) return void toast.error('Enter a category name');
    if (draft.id) {
      updateCategory(draft.id, {
        name: n,
        type: draft.type,
        icon: draft.icon,
        color: draft.color,
        parentId: draft.parentId,
      });
      toast.success('Category updated', { description: n });
    } else {
      createCategory({
        name: n,
        type: draft.type,
        icon: draft.icon,
        color: draft.color,
        parentId: draft.parentId,
        ledgerId: activeId,
      });
      toast.success('Category created', { description: n });
    }
    setDialogOpen(false);
  };

  // A child can be re-parented to any other top-level row in the same ledger.
  // A parent (one that has children of its own) cannot be re-parented — that
  // would make a 3-level tree; the mutation layer rejects it too.
  const editingHasChildren = !!(
    draft.id && list.some((c) => c.parentId === draft.id)
  );
  const reparentChoices = topLevel.filter((p) => p.id !== draft.id);

  const isCreate = draft.id == null;

  const dialog = (
    <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isCreate ? 'New category' : 'Edit category'}</DialogTitle>
          <DialogDescription>
            {isCreate
              ? draft.parentId
                ? `Added under "${list.find((c) => c.id === draft.parentId)?.name ?? '—'}" in ${active.name}.`
                : `Added as a top-level category in ${active.name}.`
              : 'Update the name, parent, type, icon and colour.'}
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label>Name</Label>
            <Input
              value={draft.name}
              onChange={(e) => setDraft({ ...draft, name: e.target.value })}
              placeholder="e.g. Travel"
              autoFocus
              onKeyDown={(e) => e.key === 'Enter' && submit()}
            />
          </div>
          {!editingHasChildren && (
            <div className="flex flex-col gap-1.5">
              <Label>Parent</Label>
              <Select
                value={draft.parentId ?? '__top__'}
                onValueChange={(v) => setDraft({ ...draft, parentId: v === '__top__' ? null : v })}
              >
                <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__top__">— Top-level —</SelectItem>
                  {reparentChoices.map((p) => (
                    <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
          <div className="flex flex-col gap-1.5">
            <Label>Type</Label>
            <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v })}>
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
            <IconPicker value={draft.icon} onChange={(v) => setDraft({ ...draft, icon: v })} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Color</Label>
            <ColorPicker value={draft.color} onChange={(v) => setDraft({ ...draft, color: v })} />
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <Button onClick={submit}>{isCreate ? 'Create' : 'Save'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  const triggerCreate = (
    <Dialog>
      <DialogTrigger asChild>
        <IconButton icon="plus" aria-label="New category" onClick={openCreateTop} />
      </DialogTrigger>
    </Dialog>
  );

  const childCount = list.filter((c) => c.parentId != null).length;
  const parentCount = topLevel.length;

  return (
    <MobilePage header={<ScreenHeader title="Categories" trailing={triggerCreate} />}>
      <div className="px-5 pb-[120px]">
        <div className="hidden items-center justify-end pt-2 pb-3 md:flex">
          <Button size="sm" variant="outline" onClick={openCreateTop}>
            <Icon name="plus" size={14} />
            New category
          </Button>
        </div>
        <div className="px-1 pb-5">
          <SchemaChip label="categories" />
          <div className="mt-1.5 font-serif text-[44px] leading-none tracking-[-1.6px]">
            {parentCount}
            <span className="text-muted-foreground italic"> parent{parentCount === 1 ? '' : 's'}</span>
            {childCount > 0 && (
              <span className="text-muted-foreground"> · {childCount} subcategor{childCount === 1 ? 'y' : 'ies'}</span>
            )}
          </div>
          <div className="text-secondary-foreground mt-1.5 text-[13px]">
            A 2-level taxonomy. Tap a card to edit; transactions can file against either level — a parent rolls up its subcategories&rsquo; totals.
          </div>
        </div>

        {tree.length === 0 && (
          <div className="text-muted-foreground rounded-[14px] border border-dashed py-10 text-center text-sm">
            No categories yet — use the + button to add one.
          </div>
        )}

        <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
          {tree.map(({ parent, children }) => (
            <div key={parent.id} className="border-border bg-card rounded-[14px] border p-4">
              <div className="flex items-center gap-3">
                <button
                  type="button"
                  onClick={() => openEdit(parent)}
                  className="flex min-w-0 flex-1 items-center gap-3 text-left"
                  aria-label={`Edit ${parent.name}`}
                >
                  <div
                    className="flex size-9 flex-shrink-0 items-center justify-center rounded-lg text-white"
                    style={{ background: colorOf(parent) }}
                  >
                    <Icon name={parent.icon ?? 'tag'} size={16} />
                  </div>
                  <div className="min-w-0">
                    <div className="truncate text-sm font-medium">{parent.name}</div>
                    <div className="text-muted-foreground mt-0.5 font-mono text-[10px] tracking-[0.5px] uppercase">
                      {parent.type}{children.length > 0 && ` · ${children.length} sub`}
                    </div>
                  </div>
                </button>
                <RowActions
                  onEdit={() => openEdit(parent)}
                  onDelete={() => {
                    deleteCategory(parent.id);
                    toast.success('Category deleted', {
                      description: children.length
                        ? `${parent.name} — ${children.length} subcategor${children.length === 1 ? 'y' : 'ies'} promoted to top-level.`
                        : parent.name,
                    });
                  }}
                  confirmTitle={`Delete ${parent.name}?`}
                  confirmDescription={
                    children.length
                      ? `Its ${children.length} subcategor${children.length === 1 ? 'y' : 'ies'} will be promoted to top-level. Transactions filed against this parent become uncategorised.`
                      : 'Transactions filed against this category become uncategorised.'
                  }
                />
              </div>

              {children.length > 0 && (
                <div className="border-border mt-3 flex flex-col gap-1 border-t border-dashed pt-2">
                  {children.map((child) => (
                    <div key={child.id} className="flex items-center gap-2 py-1.5">
                      <span className="text-muted-foreground ml-1 font-mono text-[10px]">└</span>
                      <button
                        type="button"
                        onClick={() => openEdit(child)}
                        className="min-w-0 flex-1 text-left"
                      >
                        <div className="truncate text-[13px]">{child.name}</div>
                      </button>
                      <RowActions
                        onEdit={() => openEdit(child)}
                        onDelete={() => { deleteCategory(child.id); toast.success('Subcategory deleted', { description: child.name }); }}
                        confirmTitle={`Delete ${child.name}?`}
                        confirmDescription="Transactions in this subcategory become uncategorised."
                      />
                    </div>
                  ))}
                </div>
              )}

              <button
                type="button"
                onClick={() => openCreateChild(parent.id)}
                className="text-muted-foreground hover:text-foreground mt-2 flex items-center gap-1 font-mono text-[10px]"
              >
                <Icon name="plus" size={10} stroke={2} />
                new subcategory
              </button>
            </div>
          ))}
        </div>
      </div>

      {dialog}
    </MobilePage>
  );
}
