'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
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
import {
  categoryPath,
  resolveCategoryColor,
  type CategoryRow,
} from '@/lib/db/queries/categories';
import { cn } from '@/lib/utils';

const TYPES = ['expense', 'income'] as const;
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
  const t = useTranslations('categories.dialog');
  return (
    <div className="flex flex-wrap gap-1.5">
      {COLOR_CHOICES.map((c) => (
        <button
          key={c}
          type="button"
          aria-label={t('colorAria', { color: c })}
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
  const t = useTranslations('categories');
  const tCommon = useTranslations('common');
  const categories = useFinanceStore((s) => s.categories);
  const createCategory = useFinanceStore((s) => s.createCategory);
  const updateCategory = useFinanceStore((s) => s.updateCategory);
  const deleteCategory = useFinanceStore((s) => s.deleteCategory);

  const list = categories.filter((c) => c.ledgerId === activeId);
  const byId = useMemo(() => new Map(list.map((c) => [c.id, c])), [list]);
  // 3-level forest (CATEGORIES_LEVEL3_PLAN §5.2). Each top-level node has
  // its subcategories; each subcategory has its sub-subcategories.
  // Orphan rows (parent missing) are promoted to top-level so the forest
  // is always exhaustive — same fallback the prior buildCategoryTree had.
  const forest = useMemo(() => {
    const childrenOf = new Map<string, CategoryRow[]>();
    for (const c of list) {
      if (c.parentId && byId.has(c.parentId)) {
        const arr = childrenOf.get(c.parentId);
        if (arr) arr.push(c);
        else childrenOf.set(c.parentId, [c]);
      }
    }
    type Node = { node: CategoryRow; children: { node: CategoryRow; grand: CategoryRow[] }[] };
    const tops = list.filter((c) => c.parentId == null || !byId.has(c.parentId));
    const out: Node[] = tops.map((p) => ({
      node: p,
      children: (childrenOf.get(p.id) ?? []).map((c) => ({
        node: c,
        grand: childrenOf.get(c.id) ?? [],
      })),
    }));
    return out;
  }, [list, byId]);
  // Depth of a category id in the current ledger (top-level = 1).
  const depthOfId = (id: string): number => {
    let cur: string | null = id;
    let d = 0;
    for (let hop = 0; cur != null && hop < 10; hop++) {
      const n = byId.get(cur);
      if (!n) break;
      d++;
      cur = n.parentId;
    }
    return d;
  };
  // Subtree depth of a node (leaf = 1, with children = 2, grandchildren = 3).
  const subtreeDepthOfId = (id: string): number => {
    let frontier = [id];
    let d = 1;
    for (let hop = 0; hop < 10; hop++) {
      const next = list.filter((c) => c.parentId != null && frontier.includes(c.parentId)).map((c) => c.id);
      if (!next.length) break;
      d++;
      frontier = next;
    }
    return d;
  };
  // True when candidate sits anywhere in root's subtree (including root itself).
  const isInSubtreeOf = (candidateId: string, rootId: string): boolean => {
    let cur: string | null = candidateId;
    for (let hop = 0; cur != null && hop < 10; hop++) {
      if (cur === rootId) return true;
      cur = byId.get(cur)?.parentId ?? null;
    }
    return false;
  };
  // Effective color: walk up the chain looking for a non-null color.
  // Falls back to the palette default when the whole chain has no colour.
  const colorOf = (c: CategoryRow) => resolveCategoryColor(c, byId) ?? DEFAULT_CATEGORY_HEX;

  const [query, setQuery] = useState('');
  const q = query.trim().toLowerCase();
  // Filter the 3-level forest. A query keeps a node whose own name matches
  // (with its subtree), or narrows it down to just the matching descendants
  // otherwise. Search walks all three levels.
  const filteredForest = useMemo(() => {
    if (!q) return forest;
    return forest.flatMap(({ node: parent, children }) => {
      const parentMatch = parent.name.toLowerCase().includes(q);
      if (parentMatch) return [{ node: parent, children }];
      const filteredChildren = children.flatMap(({ node: child, grand }) => {
        const childMatch = child.name.toLowerCase().includes(q);
        if (childMatch) return [{ node: child, grand }];
        const matchingGrand = grand.filter((g) => g.name.toLowerCase().includes(q));
        return matchingGrand.length ? [{ node: child, grand: matchingGrand }] : [];
      });
      return filteredChildren.length ? [{ node: parent, children: filteredChildren }] : [];
    });
  }, [forest, q]);

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
  // New child or grandchild — pre-fills the parent + inherits its type so the
  // user only has to type a name.
  const openCreateUnder = (parent: CategoryRow) => {
    setDraft({
      ...EMPTY_DRAFT,
      parentId: parent.id,
      type: parent.type,
      icon: parent.icon ?? EMPTY_DRAFT.icon,
      color: parent.color ?? colorOf(parent),
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
    if (!n) return void toast.error(t('dialog.nameRequired'));
    if (draft.id) {
      updateCategory(draft.id, {
        name: n,
        type: draft.type,
        icon: draft.icon,
        color: draft.color,
        parentId: draft.parentId,
      });
      toast.success(t('dialog.updatedToast'), { description: n });
    } else {
      createCategory({
        name: n,
        type: draft.type,
        icon: draft.icon,
        color: draft.color,
        parentId: draft.parentId,
        ledgerId: activeId,
      });
      toast.success(t('dialog.createdToast'), { description: n });
    }
    setDialogOpen(false);
  };

  // CATEGORIES_LEVEL3_PLAN §5.2: at depth ≤ 3, the picker accepts any
  // category whose depth + the editing subtree's depth ≤ 3, AND that
  // doesn't sit inside the editing subtree (cycle defence). For a new
  // category (no id) the subtree depth is 1 (just itself).
  const editingSubtreeDepth = draft.id ? subtreeDepthOfId(draft.id) : 1;
  const reparentChoices = list
    .filter((p) => {
      if (draft.id && (p.id === draft.id || isInSubtreeOf(p.id, draft.id))) return false;
      const pd = depthOfId(p.id);
      return pd + editingSubtreeDepth <= 3;
    })
    .map((c) => ({ id: c.id, label: categoryPath(c, byId) }))
    .sort((a, b) => a.label.localeCompare(b.label));

  const isCreate = draft.id == null;

  const dialog = (
    <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isCreate ? t('dialog.newTitle') : t('dialog.editTitle')}</DialogTitle>
          <DialogDescription>
            {isCreate
              ? draft.parentId
                ? t('dialog.newUnderDescription', { parent: list.find((c) => c.id === draft.parentId)?.name ?? '—', ledger: active.name })
                : t('dialog.newTopDescription', { ledger: active.name })
              : t('dialog.editDescription')}
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label>{t('dialog.name')}</Label>
            <Input
              value={draft.name}
              onChange={(e) => setDraft({ ...draft, name: e.target.value })}
              placeholder={t('dialog.namePlaceholder')}
              autoFocus
              onKeyDown={(e) => e.key === 'Enter' && submit()}
            />
          </div>
          {/* Parent picker. The reparentChoices list excludes any candidate
              that would push the editing subtree past depth 3, plus the
              editing subtree itself (cycle defence). Labels render as
              `Parent › Child › Leaf` so a level-2 candidate is unambiguous. */}
          <div className="flex flex-col gap-1.5">
            <Label>{t('dialog.parent')}</Label>
            <Select
              value={draft.parentId ?? '__top__'}
              onValueChange={(v) => setDraft({ ...draft, parentId: v === '__top__' ? null : v })}
            >
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__top__">{t('dialog.topLevel')}</SelectItem>
                {reparentChoices.map((p) => (
                  <SelectItem key={p.id} value={p.id}>{p.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>{t('dialog.type')}</Label>
            <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v })}>
              <SelectTrigger className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {TYPES.map((ty) => (
                  <SelectItem key={ty} value={ty}>{t(`types.${ty}`)}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>{t('dialog.icon')}</Label>
            <IconPicker value={draft.icon} onChange={(v) => setDraft({ ...draft, icon: v })} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>{t('dialog.color')}</Label>
            <ColorPicker value={draft.color} onChange={(v) => setDraft({ ...draft, color: v })} />
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">{tCommon('cancel')}</Button>
          </DialogClose>
          <Button onClick={submit}>{isCreate ? tCommon('create') : tCommon('save')}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  return (
    <MobilePage header={<ScreenHeader title={t('title')} />}>
      <div className="px-5 pb-[120px] md:pb-5">
        {/* Search + Add row (visible on both mobile and desktop, Tags-style) */}
        <div className="mb-3.5 flex items-center gap-2">
          <div className="bg-secondary flex h-[38px] flex-1 items-center gap-2.5 rounded-[19px] px-3.5 text-[13px]">
            <Icon name="search" size={14} className="text-muted-foreground" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label={t('searchAria')}
              placeholder={t('searchPlaceholder')}
              className="placeholder:text-muted-foreground focus-ring w-full bg-transparent outline-none"
            />
          </div>
          <Button
            onClick={openCreateTop}
            size="icon"
            className="rounded-full"
            aria-label={t('newAria')}
            title={t('newAria')}
          >
            <Icon name="plus" size={16} stroke={2} />
          </Button>
        </div>

        {forest.length === 0 ? (
          <EmptyState
            icon="tag"
            title={t('empty.title')}
            description={t('empty.description')}
          />
        ) : filteredForest.length === 0 ? (
          <div className="text-muted-foreground py-8 text-center text-sm">{t('noMatches')}</div>
        ) : (
        // Desktop: cap to the viewport (below the 77px top bar + 24px shell
        // padding + 52px search row) so the list scrolls internally instead
        // of the page. Mobile keeps natural page scrolling.
        <div className="border-border bg-card divide-border divide-y overflow-hidden rounded-[14px] border md:max-h-[calc(100dvh-180px)] md:overflow-y-auto">
          {filteredForest.flatMap(({ node: parent, children }) => {
            // While searching, a parent kept only for matching descendants is
            // forced open so the matches are visible.
            const parentForcedOpen = !!q && !parent.name.toLowerCase().includes(q);
            const parentOpen = expanded.has(parent.id) || parentForcedOpen;
            const totalDescendantCount =
              children.length + children.reduce((s, c) => s + c.grand.length, 0);
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
                    {t(`types.${parent.type as 'expense' | 'income' | 'transfer'}`)}{totalDescendantCount > 0 && t('subSummary', { count: totalDescendantCount })}
                  </div>
                </div>
                {children.length > 0 && (
                  <button
                    type="button"
                    onClick={() => toggleExpanded(parent.id)}
                    className="text-muted-foreground hover:text-foreground -mr-1 rounded-md p-1"
                    aria-label={parentOpen ? t('collapse', { name: parent.name }) : t('expand', { name: parent.name })}
                    aria-expanded={parentOpen}
                  >
                    <Icon name={parentOpen ? 'chev-d' : 'chev'} size={14} />
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => openCreateUnder(parent)}
                  className="text-muted-foreground hover:text-foreground rounded-md p-1"
                  aria-label={t('newSubAria', { name: parent.name })}
                  title={t('newSubTitle')}
                >
                  <Icon name="plus" size={14} />
                </button>
                <RowActions
                  onEdit={() => openEdit(parent)}
                  onDelete={() => {
                    deleteCategory(parent.id);
                    toast.success(t('delete.categoryToast'), {
                      description: children.length
                        ? t('delete.promotedSub', { name: parent.name, count: children.length })
                        : parent.name,
                    });
                  }}
                  confirmTitle={t('delete.confirmTitle', { name: parent.name })}
                  confirmDescription={
                    children.length
                      ? t('delete.parentWithChildrenDescription', { count: children.length })
                      : t('delete.parentEmptyDescription')
                  }
                />
              </div>
            );
            if (!parentOpen) return [parentRow];

            const childRows = children.flatMap(({ node: child, grand }) => {
              // Forced-open if the query matched a grandchild but not the child.
              const childForcedOpen = !!q && !child.name.toLowerCase().includes(q);
              const childOpen = expanded.has(child.id) || childForcedOpen;
              const childCanHaveMore = depthOfId(child.id) < 3; // depth 2 → grandchild OK
              const childRow = (
                <div
                  key={child.id}
                  className="flex items-center gap-2 py-2 pr-3 pl-12 transition-colors hover:bg-secondary/50"
                >
                  <div
                    className="flex size-6 flex-shrink-0 items-center justify-center rounded-md text-white"
                    style={{ background: colorOf(child) }}
                  >
                    <Icon name={child.icon ?? parent.icon ?? 'tag'} size={12} />
                  </div>
                  <div className="min-w-0 flex-1 truncate text-[13px]">{child.name}</div>
                  {grand.length > 0 && (
                    <button
                      type="button"
                      onClick={() => toggleExpanded(child.id)}
                      className="text-muted-foreground hover:text-foreground -mr-1 rounded-md p-1"
                      aria-label={childOpen ? t('collapse', { name: child.name }) : t('expand', { name: child.name })}
                      aria-expanded={childOpen}
                    >
                      <Icon name={childOpen ? 'chev-d' : 'chev'} size={12} />
                    </button>
                  )}
                  {childCanHaveMore && (
                    <button
                      type="button"
                      onClick={() => openCreateUnder(child)}
                      className="text-muted-foreground hover:text-foreground rounded-md p-1"
                      aria-label={t('newSubSubAria', { name: child.name })}
                      title={t('newSubSubTitle')}
                    >
                      <Icon name="plus" size={12} />
                    </button>
                  )}
                  <RowActions
                    onEdit={() => openEdit(child)}
                    onDelete={() => {
                      deleteCategory(child.id);
                      toast.success(t('delete.subcategoryToast'), {
                        description: grand.length
                          ? t('delete.promotedSubSub', { name: child.name, count: grand.length })
                          : child.name,
                      });
                    }}
                    confirmTitle={t('delete.confirmTitle', { name: child.name })}
                    confirmDescription={
                      grand.length
                        ? t('delete.childWithGrandDescription', { count: grand.length })
                        : t('delete.childEmptyDescription')
                    }
                  />
                </div>
              );
              if (!childOpen) return [childRow];

              const grandRows = grand.map((g) => (
                <div
                  key={g.id}
                  className="flex items-center gap-2 py-1.5 pr-3 pl-20 transition-colors hover:bg-secondary/50"
                >
                  <div
                    className="flex size-5 flex-shrink-0 items-center justify-center rounded-md text-white"
                    style={{ background: colorOf(g) }}
                  >
                    <Icon name={g.icon ?? child.icon ?? parent.icon ?? 'tag'} size={10} />
                  </div>
                  <div className="min-w-0 flex-1 truncate text-[12px]">{g.name}</div>
                  <RowActions
                    onEdit={() => openEdit(g)}
                    onDelete={() => { deleteCategory(g.id); toast.success(t('delete.subSubcategoryToast'), { description: g.name }); }}
                    confirmTitle={t('delete.confirmTitle', { name: g.name })}
                    confirmDescription={t('delete.grandDescription')}
                  />
                </div>
              ));
              return [childRow, ...grandRows];
            });
            return [parentRow, ...childRows];
          })}
        </div>
        )}
      </div>

      {dialog}
    </MobilePage>
  );
}
