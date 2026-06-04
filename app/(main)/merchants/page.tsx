'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { RowActions } from '@/components/RowActions';
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
                UNVERIFIED
              </span>
            )}
          </div>
          <div className="flex items-center gap-1">
            {c.txCount != null && <div className="text-muted-foreground font-mono text-[11px]">{c.txCount}×</div>}
            <RowActions
              onEdit={onEdit}
              onDelete={onDelete}
              confirmTitle={`Delete ${c.name}?`}
              confirmDescription="The merchant is removed; transactions that referenced it are left untouched."
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
              toast.success(`${c.name} verified`);
            }}
          >
            <Icon name="check" size={12} />
            Verify
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

  // Drive the list off the projected counterparties; fall back to the static
  // seed only until the store hydrates so the first paint isn't empty.
  const projected = counterparties.filter((c) => c.ledgerId === CP_LEDGER);
  const rows: MerchantData[] = projected.length
    ? projected.map((c) => ({ id: c.id, name: c.name, verified: c.verified, color: colorFor(c.id, c.name), txCount: MOCK_BY_ID.get(c.id)?.txCount ?? null }))
    : LEDGER.counterparties.map((c) => ({ id: c.id, name: c.name, verified: c.verified === 1, color: oklchToHex(0.65, 0.2, c.hue), txCount: c.txCount }));

  const q = query.toLowerCase();
  const list = rows.filter((c) => !q || c.name.toLowerCase().includes(q));
  const unverified = rows.filter((c) => !c.verified).length;

  const [createOpen, setCreateOpen] = useState(false);
  const [newName, setNewName] = useState('');
  const submitCreate = () => {
    const name = newName.trim();
    if (!name) return void toast.error('Enter a merchant name');
    createCounterparty({ name, ledgerId: CP_LEDGER });
    toast.success('Merchant added', { description: name });
    setNewName('');
    setCreateOpen(false);
  };

  const [editing, setEditing] = useState<{ id: string; name: string } | null>(null);
  const submitEdit = () => {
    if (!editing) return;
    const name = editing.name.trim();
    if (!name) return void toast.error('Enter a merchant name');
    updateCounterparty(editing.id, { name });
    toast.success('Merchant updated', { description: name });
    setEditing(null);
  };

  return (
    <MobilePage
      header={<ScreenHeader title="Merchants" trailing={<IconButton icon="plus" aria-label="New merchant" onClick={() => setCreateOpen(true)} />} />}
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-[18px]">
          <div className="flex items-baseline gap-3.5">
            <div>
              <div className="font-serif text-[40px] leading-none tracking-[-1.4px]">{rows.length}</div>
              <div className="text-muted-foreground mt-1 font-mono text-[9px] tracking-[1px]">STANDARDISED</div>
            </div>
            <div className="bg-border h-8 w-px" />
            <div>
              <div className="text-warning font-serif text-[40px] leading-none tracking-[-1.4px]">{unverified}</div>
              <div className="text-muted-foreground mt-1 font-mono text-[9px] tracking-[1px]">UNVERIFIED</div>
            </div>
          </div>
        </div>

        <div className="hidden items-center justify-end pb-3 md:flex">
          <Button size="sm" variant="outline" onClick={() => setCreateOpen(true)}>
            <Icon name="plus" size={14} />
            New merchant
          </Button>
        </div>

        <div className="bg-secondary mb-3.5 flex h-[38px] items-center gap-2.5 rounded-[19px] px-3.5 text-[13px]">
          <Icon name="search" size={14} className="text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label="Search merchants" placeholder="Search merchants…"
            className="placeholder:text-muted-foreground w-full bg-transparent outline-none"
          />
        </div>

        <div className="flex flex-col">
          {list.map((c, i) => (
            <MerchantRow
              key={c.id}
              c={c}
              border={i > 0}
              onEdit={() => setEditing({ id: c.id, name: c.name })}
              onDelete={() => { deleteCounterparty(c.id); toast.success('Merchant deleted', { description: c.name }); }}
            />
          ))}
          {list.length === 0 && (
            <div className="text-muted-foreground py-8 text-center text-sm">No matches</div>
          )}
        </div>
      </div>

      <Dialog open={createOpen} onOpenChange={setCreateOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>New merchant</DialogTitle>
            <DialogDescription>A standardised counterparty for matching transactions.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label>Name</Label>
              <Input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="e.g. Starbucks" autoFocus onKeyDown={(e) => e.key === 'Enter' && submitCreate()} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitCreate}>Add</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit merchant</DialogTitle>
            <DialogDescription>Rename this merchant.</DialogDescription>
          </DialogHeader>
          {editing && (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Name</Label>
                <Input value={editing.name} onChange={(e) => setEditing((p) => (p ? { ...p, name: e.target.value } : p))} autoFocus />
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
