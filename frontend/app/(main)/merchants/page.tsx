'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Check, Plus, Search } from '@/components/icons';
import { MobilePage } from '@/components/mobile-page';
import { ScreenHeader } from '@/components/ui/screen-header';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { RowActions } from '@/components/row-actions';
import { LEDGER } from '@/lib/data';
import { oklchToHex } from '@/lib/colors';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

const CP_LEDGER = 'personal';

interface MerchantData {
  id: string;
  name: string;
  verified: boolean;
  color: string;
  txCount: number | null;
}

// Decorative-only fields (color/txCount) the table doesn't store — fall back
// to the static seed by id, deriving a stable hue→hex for merchants created
// in-app.
const MOCK_BY_ID = new Map(LEDGER.counterparties.map((c) => [c.id, c]));
const colorFor = (id: string, name: string): string => {
  const hue = MOCK_BY_ID.get(id)?.hue ?? [...name].reduce((a, ch) => a + ch.charCodeAt(0), 0) % 360;
  return oklchToHex(0.65, 0.2, hue);
};

function MerchantRow({ c, border, onEdit, onDelete }: { c: MerchantData; border: boolean; onEdit: () => void; onDelete: () => void }) {
  const verifyCounterparty = useFinanceStore((s) => s.verifyCounterparty);
  const t = useTranslations('merchants');

  return (
    <div className={cn('flex items-start gap-3 py-3.5', border && 'border-border border-t')}>
      <div
        className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg font-mono text-[10px] font-semibold text-white"
        style={{ background: c.color }}
      >
        {c.name.slice(0, 2).toUpperCase()}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-2">
          <div className="flex items-center gap-2">
            <div className="text-sm font-medium">{c.name}</div>
            {!c.verified && (
              <span className="border-warning/40 text-warning rounded border px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px]">
                {t('unverifiedChip')}
              </span>
            )}
          </div>
          <div className="flex items-center gap-1">
            {c.txCount != null && <div className="text-muted-foreground font-mono text-[11px]">{c.txCount}×</div>}
            <RowActions
              onEdit={onEdit}
              onDelete={onDelete}
              confirmTitle={t('deleteConfirm.title', { name: c.name })}
              confirmDescription={t('deleteConfirm.description')}
            />
          </div>
        </div>
        {!c.verified && (
          <Button
            size="sm"
            variant="outline"
            className="mt-2 h-7"
            onClick={() => {
              verifyCounterparty(c.id);
              toast.success(t('verifiedToast', { name: c.name }));
            }}
          >
            <Check size={12} />
            {t('verifyButton')}
          </Button>
        )}
      </div>
    </div>
  );
}

export default function MerchantsPage() {
  const counterparties = useFinanceStore((s) => s.counterparties);
  const createCounterparty = useFinanceStore((s) => s.createCounterparty);
  const updateCounterparty = useFinanceStore((s) => s.updateCounterparty);
  const deleteCounterparty = useFinanceStore((s) => s.deleteCounterparty);
  const [query, setQuery] = useState('');
  const t = useTranslations('merchants');
  const tCommon = useTranslations('common');

  // Drive the list off the projected counterparties; fall back to the static
  // seed only until the store hydrates so the first paint isn't empty.
  const projected = counterparties; // merchants are global (no per-ledger filter)
  const rows: MerchantData[] = projected.length
    ? projected.map((c) => ({ id: c.id, name: c.name, verified: c.verified, color: colorFor(c.id, c.name), txCount: MOCK_BY_ID.get(c.id)?.txCount ?? null }))
    : LEDGER.counterparties.map((c) => ({ id: c.id, name: c.name, verified: c.verified === 1, color: oklchToHex(0.65, 0.2, c.hue), txCount: c.txCount }));

  const q = query.toLowerCase();
  const list = rows.filter((c) => !q || c.name.toLowerCase().includes(q));

  const [createOpen, setCreateOpen] = useState(false);
  const [newName, setNewName] = useState('');
  const submitCreate = () => {
    const name = newName.trim();
    if (!name) return void toast.error(t('createDialog.createErrorEmpty'));
    createCounterparty({ name, ledgerId: CP_LEDGER });
    toast.success(t('createDialog.createdToast'), { description: name });
    setNewName('');
    setCreateOpen(false);
  };

  const [editing, setEditing] = useState<{ id: string; name: string } | null>(null);
  const submitEdit = () => {
    if (!editing) return;
    const name = editing.name.trim();
    if (!name) return void toast.error(t('createDialog.createErrorEmpty'));
    updateCounterparty(editing.id, { name });
    toast.success(t('editDialog.updatedToast'), { description: name });
    setEditing(null);
  };

  return (
    <MobilePage
      header={<ScreenHeader title={t('title')} />}
    >
      <div className="px-5 pb-[120px] md:pb-5">
        {/* Search + Add row (visible on both mobile and desktop, Tags-style) */}
        <div className="mb-3.5 flex items-center gap-2">
          <div className="bg-secondary flex h-[38px] flex-1 items-center gap-2.5 rounded-[19px] px-3.5 text-[13px]">
            <Search size={14} className="text-muted-foreground" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label={t('searchAria')} placeholder={t('searchPlaceholder')}
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
            <Plus size={16} strokeWidth={2} />
          </Button>
        </div>

        {/* Desktop: cap to the viewport (below the 77px top bar + 24px shell
            padding + 52px search row) so the list scrolls internally instead
            of the page. Mobile keeps natural page scrolling. */}
        <div className="flex flex-col md:max-h-[calc(100dvh-180px)] md:overflow-y-auto">
          {list.map((c, i) => (
            <MerchantRow
              key={c.id}
              c={c}
              border={i > 0}
              onEdit={() => setEditing({ id: c.id, name: c.name })}
              onDelete={() => { deleteCounterparty(c.id); toast.success(t('deleteConfirm.deletedToast'), { description: c.name }); }}
            />
          ))}
          {list.length === 0 && (
            <div className="text-muted-foreground py-8 text-center text-sm">{t('noMatches')}</div>
          )}
        </div>
      </div>

      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('createDialog.title')}</DialogTitle>
            <DialogDescription>{t('createDialog.description')}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>{t('createDialog.name')}</Label>
              <Input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder={t('createDialog.namePlaceholder')} autoFocus onKeyDown={(e) => e.key === 'Enter' && submitCreate()} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={submitCreate}>{t('createDialog.create')}</Button>
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
