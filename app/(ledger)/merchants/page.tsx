'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { LEDGER } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

type Counterparty = (typeof LEDGER.counterparties)[number];

function MerchantRow({
  c,
  verified,
  aliases,
  border,
}: {
  c: Counterparty;
  verified: boolean;
  aliases: string[];
  border: boolean;
}) {
  const verifyCounterparty = useFinanceStore((s) => s.verifyCounterparty);
  const addAlias = useFinanceStore((s) => s.addAlias);
  const [adding, setAdding] = useState(false);
  const [draft, setDraft] = useState('');

  const submitAlias = () => {
    const a = draft.trim();
    if (a) {
      addAlias(c.id, a);
      toast.success(`Alias added to ${c.name}`);
    }
    setDraft('');
    setAdding(false);
  };

  return (
    <div className={cn('flex items-start gap-3 py-3.5', border && 'border-border border-t')}>
      <div
        className="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg font-mono text-[10px] font-semibold text-white"
        style={{ background: `oklch(0.65 0.2 ${c.hue})` }}
      >
        {c.name.slice(0, 2).toUpperCase()}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-2">
          <div className="flex items-center gap-2">
            <div className="text-sm font-medium">{c.name}</div>
            {!verified && (
              <span className="border-warning/40 text-warning rounded border px-1.5 py-0.5 font-mono text-[9px] tracking-[0.6px]">
                UNVERIFIED
              </span>
            )}
          </div>
          <div className="text-muted-foreground font-mono text-[11px]">{c.txCount}×</div>
        </div>
        <div className="text-muted-foreground mt-1 text-[11px]">
          {c.category} <span className="mx-[5px]">·</span>
          <span className="text-secondary-foreground font-mono text-[10px]">aliases:</span>
        </div>
        <div className="mt-1.5 flex flex-wrap items-center gap-1">
          {aliases.map((a) => (
            <span
              key={a}
              className="bg-secondary text-secondary-foreground rounded px-[7px] py-0.5 font-mono text-[10px] tracking-[0.2px]"
            >
              {a}
            </span>
          ))}
          {adding ? (
            <span className="flex items-center gap-1">
              <Input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && submitAlias()}
                placeholder="ALIAS"
                autoFocus
                className="h-6 w-28 px-2 font-mono text-[10px]"
              />
              <Button size="sm" className="h-6 px-2 text-[10px]" onClick={submitAlias}>
                Add
              </Button>
            </span>
          ) : (
            <button
              type="button"
              onClick={() => setAdding(true)}
              className="text-muted-foreground hover:text-foreground rounded border border-dashed px-[7px] py-0.5 font-mono text-[10px]"
            >
              + alias
            </button>
          )}
        </div>
        {!verified && (
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
  const verifiedExtra = useFinanceStore((s) => s.verifiedExtra);
  const aliasExtra = useFinanceStore((s) => s.aliasExtra);
  const [query, setQuery] = useState('');

  const isVerified = (c: Counterparty) => c.verified === 1 || verifiedExtra.includes(c.id);
  const aliasesOf = (c: Counterparty) => [...c.aliases, ...(aliasExtra[c.id] ?? [])];

  const q = query.toLowerCase();
  const list = LEDGER.counterparties.filter(
    (c) => !q || c.name.toLowerCase().includes(q) || aliasesOf(c).some((a) => a.toLowerCase().includes(q)),
  );
  const unverified = LEDGER.counterparties.filter((c) => !isVerified(c)).length;

  return (
    <MobilePage
      header={<ScreenHeader title="Merchants" trailing={<IconButton icon="plus" aria-label="New merchant" />} />}
    >
      <div className="px-5 pb-[120px]">
        <div className="px-1 pb-[18px]">
          <SchemaChip label="counterparties" />
          <div className="mt-2 flex items-baseline gap-3.5">
            <div>
              <div className="font-serif text-[40px] leading-none tracking-[-1.4px]">
                {LEDGER.counterparties.length}
              </div>
              <div className="text-muted-foreground mt-1 font-mono text-[9px] tracking-[1px]">STANDARDISED</div>
            </div>
            <div className="bg-border h-8 w-px" />
            <div>
              <div className="text-warning font-serif text-[40px] leading-none tracking-[-1.4px]">
                {unverified}
              </div>
              <div className="text-muted-foreground mt-1 font-mono text-[9px] tracking-[1px]">UNVERIFIED</div>
            </div>
          </div>
        </div>

        <div className="bg-secondary mb-3.5 flex h-[38px] items-center gap-2.5 rounded-[19px] px-3.5 text-[13px]">
          <Icon name="search" size={14} className="text-muted-foreground" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search merchants & aliases…"
            className="placeholder:text-muted-foreground w-full bg-transparent outline-none"
          />
        </div>

        <div className="flex flex-col">
          {list.map((c, i) => (
            <MerchantRow key={c.id} c={c} verified={isVerified(c)} aliases={aliasesOf(c)} border={i > 0} />
          ))}
          {list.length === 0 && (
            <div className="text-muted-foreground py-8 text-center text-sm">No matches</div>
          )}
        </div>
      </div>
    </MobilePage>
  );
}
