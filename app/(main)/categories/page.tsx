'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { EmptyState } from '@/components/empty-state';
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

  const [query, setQuery] = useState('');
  const q = query.trim().toLowerCase();
  // A query keeps a parent whose own name matches (with all its children), or
  // narrows it down to just the matching subcategories otherwise.
  const filteredTree = useMemo(() => {
    if (!q) return tree;
    return tree.flatMap(({ parent, children }) => {
      if (parent.name.toLowerCase().includes(q)) return [{ parent, children }];
      const matching = children.filter((c) => c.name.toLowerCase().includes(q));
      return matching.length ? [{ parent, children: matching }] : [];
    });
  }, [tree, q]);

  // Main categories are collapsed by default; their ids are added when the
  // chevron is clicked, revealing the subcategory rows beneath.
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set());
  const toggleExpanded = (id: string) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const [draft, setDraft] = useState<CatDraft>(EMPTY_DRAFT);
  const [dialogOpen, setDialogOpen] = useState(false);

  const openCreateTop = () => {
    setDraft(EMPTY_DRAFT);
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

  return (
    <MobilePage header={<ScreenHeader title="Categories" />}>
      <div className="px-5 pb-[120px] md:pb-5">
        {/* Search + Add row (visible on both mobile and desktop, Tags-style) */}
        <div className="mb-3.5 flex items-center gap-2">
          <div className="bg-secondary flex h-[38px] flex-1 items-center gap-2.5 rounded-[19px] px-3.5 text-[13px]">
            <Icon name="search" size={14} className="text-muted-foreground" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label="Search categories"
              placeholder="Search categories…"
              className="placeholder:text-muted-foreground focus-ring w-full bg-transparent outline-none"
            />
          </div>
          <Button
            onClick={openCreateTop}
            size="icon"
            className="rounded-full"
            aria-label="New category"
            title="New category"
          >
            <Icon name="plus" size={16} stroke={2} />
          </Button>
        </div>

        {tree.length === 0 ? (
          <EmptyState
            icon="tag"
            title="No categories yet"
            description="Tap + to add one — they slot into the budget rings and reports."
          />
        ) : filteredTree.length === 0 ? (
          <div className="text-muted-foreground py-8 text-center text-sm">No matches</div>
        ) : (
        // Desktop: cap to the viewport (below the 77px top bar + 24px shell
        // padding + 52px search row) so the list scrolls internally instead
        // of the page. Mobile keeps natural page scrolling.
        <div className="border-border bg-card divide-border divide-y overflow-hidden rounded-[14px] border md:max-h-[calc(100dvh-180px)] md:overflow-y-auto">
          {filteredTree.flatMap(({ parent, children }) => {
            // While searching, a parent kept only for its matching children is
            // forced open so those matches are actually visible.
            const isOpen = expanded.has(parent.id) || (!!q && !parent.name.toLowerCase().includes(q));
            const parentRow = (
              <div
                key={parent.id}
                className="flex items-center gap-3 px-4 py-3.5 transition-colors hover:bg-secondary/50"
              >
                <div
                  className="flex size-9 flex-shrink-0 items-center justify-center rounded-lg text-white"
                  style={{ background: colorOf(parent) }}
                >
                  <Icon name={parent.icon ?? 'tag'} size={16} />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-medium">{parent.name}</div>
                  <div className="text-muted-foreground mt-0.5 font-mono text-[10px] tracking-[0.5px] uppercase">
                    {parent.type}{children.length > 0 && ` · ${children.length} sub`}
                  </div>
                </div>
                {children.length > 0 && (
                  <button
                    type="button"
                    onClick={() => toggleExpanded(parent.id)}
                    className="text-muted-foreground hover:text-foreground -mr-1 rounded-md p-1"
                    aria-label={isOpen ? `Collapse ${parent.name}` : `Expand ${parent.name}`}
                    aria-expanded={isOpen}
                  >
                    <Icon name={isOpen ? 'chev-d' : 'chev'} size={14} />
                  </button>
                )}
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
            );
            const childRows = isOpen ? children.map((child) => (
              <div
                key={child.id}
                className="flex items-center gap-2 py-2 pr-3 pl-12 transition-colors hover:bg-secondary/50"
              >
                <div
                  className="flex size-6 flex-shrink-0 items-center justify-center rounded-md text-white"
                  style={{ background: child.color ?? colorOf(parent) }}
                >
                  <Icon name={child.icon ?? parent.icon ?? 'tag'} size={12} />
                </div>
                <div className="min-w-0 flex-1 truncate text-[13px]">{child.name}</div>
                <RowActions
                  onEdit={() => openEdit(child)}
                  onDelete={() => { deleteCategory(child.id); toast.success('Subcategory deleted', { description: child.name }); }}
                  confirmTitle={`Delete ${child.name}?`}
                  confirmDescription="Transactions in this subcategory become uncategorised."
                />
              </div>
            )) : [];
            return [parentRow, ...childRows];
          })}
        </div>
        )}
      </div>

      {dialog}
    </MobilePage>
  );
}
