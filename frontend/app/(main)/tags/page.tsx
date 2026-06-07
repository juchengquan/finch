'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
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
  const t = useTranslations('tags');
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

export default function TagsPage() {
  const { active, activeId } = useLedger();
  const tags = useFinanceStore((s) => s.tags);
  const createTag = useFinanceStore((s) => s.createTag);
  const updateTag = useFinanceStore((s) => s.updateTag);
  const deleteTag = useFinanceStore((s) => s.deleteTag);
  const t = useTranslations('tags');
  const tCommon = useTranslations('common');

  const list = tags.filter((tg) => tg.ledgerId === activeId);

  const [query, setQuery] = useState('');
  const q = query.toLowerCase();
  const filteredList = q ? list.filter((tg) => tg.name.toLowerCase().includes(q)) : list;

  const [createOpen, setCreateOpen] = useState(false);
  const [name, setName] = useState('');
  const [color, setColor] = useState(DEFAULT_TAG_HEX);
  const submitCreate = () => {
    const n = name.trim();
    if (!n) return void toast.error(t('createDialog.createErrorEmpty'));
    createTag({ name: n, color, ledgerId: activeId });
    toast.success(t('createDialog.createdToast'), { description: n });
    setName('');
    setColor(DEFAULT_TAG_HEX);
    setCreateOpen(false);
  };

  const [editing, setEditing] = useState<{ id: string; name: string; color: string } | null>(null);
  const submitEdit = () => {
    if (!editing) return;
    const n = editing.name.trim();
    if (!n) return void toast.error(t('createDialog.createErrorEmpty'));
    updateTag(editing.id, { name: n, color: editing.color });
    toast.success(t('editDialog.updatedToast'), { description: n });
    setEditing(null);
  };

  return (
    <MobilePage
      header={<ScreenHeader title={t('title')} />}
    >
      <div className="px-5 pb-[120px] md:pb-5">
        {/* Search + Add row (visible on both mobile and desktop, Categories-style) */}
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
            onClick={() => setCreateOpen(true)}
            size="icon"
            className="rounded-full"
            aria-label={t('newAria')}
            title={t('newAria')}
          >
            <Icon name="plus" size={16} stroke={2} />
          </Button>
        </div>

        {list.length === 0 ? (
          <div className="text-muted-foreground rounded-[14px] border border-dashed py-10 text-center text-sm">
            {t('emptyHint')}
          </div>
        ) : filteredList.length === 0 ? (
          <div className="text-muted-foreground py-8 text-center text-sm">{t('noMatches')}</div>
        ) : (
          // Desktop: cap to the viewport (below the 77px top bar + 24px shell
          // padding + 52px search row) so the list scrolls internally instead
          // of the page. Mobile keeps natural page scrolling.
          <div className="border-border bg-card divide-border divide-y overflow-hidden rounded-[14px] border md:max-h-[calc(100dvh-180px)] md:overflow-y-auto">
            {filteredList.map((tg) => (
              <div
                key={tg.id}
                className="flex items-center gap-3 px-4 py-3.5 transition-colors hover:bg-secondary/50"
              >
                <span
                  className="size-2.5 shrink-0 rounded-full"
                  style={{ background: tg.color ?? DEFAULT_TAG_HEX }}
                />
                <div className="min-w-0 flex-1 text-sm font-medium">{tg.name}</div>
                <RowActions
                  onEdit={() => setEditing({ id: tg.id, name: tg.name, color: tg.color ?? DEFAULT_TAG_HEX })}
                  onDelete={() => { deleteTag(tg.id); toast.success(t('deleteConfirm.deletedToast'), { description: tg.name }); }}
                  confirmTitle={t('deleteConfirm.title', { name: tg.name })}
                  confirmDescription={t('deleteConfirm.description')}
                />
              </div>
            ))}
          </div>
        )}
      </div>

      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('createDialog.title')}</DialogTitle>
            <DialogDescription>{t('createDialog.description', { ledger: active.name })}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>{t('createDialog.name')}</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder={t('createDialog.namePlaceholder')} autoFocus onKeyDown={(e) => e.key === 'Enter' && submitCreate()} />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label>{t('createDialog.color')}</Label>
              <ColorPicker value={color} onChange={setColor} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={submitCreate}>{tCommon('create')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('editDialog.title')}</DialogTitle>
            <DialogDescription>{t('editDialog.description')}</DialogDescription>
          </DialogHeader>
          {editing && (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>{t('createDialog.name')}</Label>
                <Input value={editing.name} onChange={(e) => setEditing((p) => (p ? { ...p, name: e.target.value } : p))} autoFocus />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>{t('createDialog.color')}</Label>
                <ColorPicker value={editing.color} onChange={(v) => setEditing((p) => (p ? { ...p, color: v } : p))} />
              </div>
            </div>
          )}
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={submitEdit}>{tCommon('save')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
