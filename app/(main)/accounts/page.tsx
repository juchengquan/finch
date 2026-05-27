'use client';

import Link from 'next/link';
import { useState } from 'react';
import { toast } from 'sonner';
import { Icon, Money, CatBar, Sparkline } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { Accordion, AccordionItem, AccordionTrigger, AccordionContent } from '@/components/ui/accordion';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useTransactionSheet } from '@/components/transaction-sheet';
import { useFinanceStore } from '@/lib/store';
import { MOCK, catById } from '@/lib/data';
import { ACCOUNT_TYPE_OPTIONS } from '@/lib/account-types';
import { accountBalance, netWorthSeries } from '@/lib/select';
import { cn } from '@/lib/utils';

const DEFAULT_OPEN_GROUPS = ['cash', 'credit', 'invest'];

type GroupWithAccounts = {
  id: string;
  name: string;
  accounts: { id: string; name: string; last4: string; color: string }[];
};

// Collapsible account groups, shared by the mobile column and the desktop
// left column. Empty groups render a collapsible "Add account" affordance.
function AccountGroupAccordion({
  groups,
  balanceOf,
  fmt,
  defaultOpen,
  onAddAccount,
}: {
  groups: GroupWithAccounts[];
  balanceOf: (id: string) => number;
  fmt: (n: number) => string;
  defaultOpen: string[];
  onAddAccount: (groupId: string) => void;
}) {
  return (
    <Accordion type="multiple" defaultValue={defaultOpen}>
      {groups.map((g) => {
        const groupTotal = g.accounts.reduce((s, a) => s + balanceOf(a.id), 0);
        const empty = g.accounts.length === 0;
        return (
          <AccordionItem key={g.id} value={g.id}>
            <AccordionTrigger chevronSide="left">
              <div className="flex min-w-0 flex-1 items-center gap-2.5">
                <div className="flex-1 font-serif text-lg italic -tracking-[0.2px]">{g.name}</div>
                <span className={cn('font-mono text-[11px] tracking-[0.3px] tabular-nums', empty ? 'text-muted-foreground' : 'text-secondary-foreground')}>
                  {empty ? '—' : `${g.accounts.length} · ${groupTotal < 0 ? '−' : ''}${fmt(Math.abs(groupTotal))}`}
                </span>
              </div>
            </AccordionTrigger>
            <AccordionContent>
              {empty ? (
                <button type="button" onClick={() => onAddAccount(g.id)} className="border-border text-muted-foreground hover:text-foreground flex h-[52px] w-full cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed text-xs transition-colors">
                  <Icon name="plus" size={14} />Add account
                </button>
              ) : (
                <div className="bg-card border-border rounded-xl border">
                  {g.accounts.map((a, i) => {
                    const bal = balanceOf(a.id);
                    return (
                      <Link key={a.id} href={`/accounts/${a.id}`} className={cn('flex cursor-pointer items-center gap-3 p-3.5 text-inherit no-underline', i && 'border-border border-t-[0.5px]')}>
                        <div className="flex size-[38px] shrink-0 items-center justify-center rounded-lg font-mono text-[10px] font-semibold tracking-[0.5px] text-white" style={{ background: a.color }}>{a.last4.slice(-2)}</div>
                        <div className="min-w-0 flex-1">
                          <div className="text-sm font-medium">{a.name}</div>
                          <div className="text-muted-foreground mt-0.5 font-mono text-[10px] tracking-[0.5px]">•••• {a.last4}</div>
                        </div>
                        <div className="flex items-center gap-2.5">
                          <div className="min-w-[70px] text-right">
                            <div className={cn('font-sans text-base font-medium leading-none tabular-nums', bal < 0 ? 'text-destructive' : 'text-foreground')}>
                              {bal < 0 ? '−' : ''}{fmt(Math.abs(bal))}
                            </div>
                          </div>
                          <Icon name="chev" size={12} className="text-muted-foreground shrink-0" />
                        </div>
                      </Link>
                    );
                  })}
                  <button type="button" onClick={() => onAddAccount(g.id)} className="border-border text-muted-foreground hover:text-foreground flex w-full cursor-pointer items-center justify-center gap-2 border-t-[0.5px] px-3.5 py-2.5 text-xs transition-colors">
                    <Icon name="plus" size={13} />Add account
                  </button>
                </div>
              )}
            </AccordionContent>
          </AccordionItem>
        );
      })}
    </Accordion>
  );
}

const EMPTY_DRAFT = { name: '', type: 'savings', group: 'cash', openingBalance: '', last4: '', color: '#3a4a5f' };

export default function AccountsPage() {
  const { fmt } = useMoney();
  const { active, activeId } = useLedger();
  const { openTransaction } = useTransactionSheet();
  const allTxns = useFinanceStore((s) => s.transactions);
  const accounts = useFinanceStore((s) => s.accounts);
  const createAccount = useFinanceStore((s) => s.createAccount);
  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === activeId);

  const [createOpen, setCreateOpen] = useState(false);
  const [draft, setDraft] = useState(EMPTY_DRAFT);

  const openCreate = (groupId?: string) => {
    setDraft({ ...EMPTY_DRAFT, group: groupId ?? 'cash' });
    setCreateOpen(true);
  };

  const saveCreate = () => {
    const name = draft.name.trim();
    if (!name) return;
    createAccount({
      name,
      type: draft.type,
      currency: active.base,
      groupId: draft.group,
      openingBalance: Number(draft.openingBalance) || 0,
      color: draft.color,
      last4: draft.last4.trim() || null,
      ledgerId: activeId,
    });
    toast.success('Account created', { description: name });
    setCreateOpen(false);
  };

  // Accounts (name/last4/color/group) and balances now come from the projected
  // DB rows; the static mock is only a pre-hydration fallback so first paint
  // isn't empty.
  const ledgerAccountRows = accounts.filter((a) => a.ledgerId === activeId);
  const balanceOf = (id: string) => accountBalance(ledgerAccountRows, id);

  const ledgerAccounts = ledgerAccountRows.length
    ? ledgerAccountRows.map((a) => ({ id: a.id, name: a.name, last4: a.last4 ?? '', color: a.color ?? '#6b7280', group: a.groupId ?? '' }))
    : MOCK.accounts
        .filter((a) => ((a as { ledger?: string }).ledger ?? 'personal') === activeId)
        .map((a) => ({ id: a.id, name: a.name, last4: a.last4, color: a.color, group: a.group }));

  const trailing = (
    <div className="flex items-center gap-1">
      <IconButton icon="search" aria-label="Search" />
      <IconButton icon="plus" aria-label="Add account" onClick={() => openCreate()} />
    </div>
  );

  const createDialog = (
    <Dialog open={createOpen} onOpenChange={setCreateOpen}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New account</DialogTitle>
          <DialogDescription>Added to {active.name}</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="new-name">Name</Label>
            <Input id="new-name" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} autoFocus />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="new-type">Type</Label>
              <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v })}>
                <SelectTrigger id="new-type" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {ACCOUNT_TYPE_OPTIONS.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="new-group">Group</Label>
              <Select value={draft.group} onValueChange={(v) => setDraft({ ...draft, group: v })}>
                <SelectTrigger id="new-group" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {MOCK.accountGroups.map((g) => <SelectItem key={g.id} value={g.id}>{g.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="new-balance">Opening balance ({active.base})</Label>
              <Input id="new-balance" inputMode="decimal" value={draft.openingBalance} onChange={(e) => setDraft({ ...draft, openingBalance: e.target.value })} placeholder="0.00" />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="new-last4">Number (last 4)</Label>
              <Input id="new-last4" inputMode="numeric" maxLength={4} value={draft.last4} onChange={(e) => setDraft({ ...draft, last4: e.target.value })} />
            </div>
          </div>
          <div className="flex items-center justify-between gap-3">
            <Label htmlFor="new-color">Card color</Label>
            <input id="new-color" type="color" value={draft.color} onChange={(e) => setDraft({ ...draft, color: e.target.value })} className="size-9 cursor-pointer rounded-md border border-border bg-transparent" />
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <Button onClick={saveCreate} disabled={!draft.name.trim()}>Create</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  if (ledgerAccounts.length === 0) {
    return (
      <MobilePage>
        <ScreenHeader title="Accounts" trailing={trailing} />
        <div className="text-muted-foreground px-5 pt-16 text-center text-sm">
          No accounts linked in <span className="text-foreground font-medium">{active.name}</span> yet.
        </div>
        {createDialog}
      </MobilePage>
    );
  }

  const total = ledgerAccounts.reduce((s, a) => s + balanceOf(a.id), 0);
  const nwSeries = netWorthSeries(allTxns, accounts, activeId);
  const groupedAccounts = MOCK.accountGroups.map((g) => ({
    ...g,
    accounts: ledgerAccounts.filter((a) => a.group === g.id),
  }));

  return (
    <MobilePage>
      <ScreenHeader title="Accounts" trailing={trailing} />

      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Net worth · all accounts"
          value={<Money value={total} mono={false} className="font-serif" />}
          sublabel={<span className="text-success">+ <Money value={812} /> this month</span>}
        />
        {nwSeries.length > 2 && (
          <div className="mt-3">
            <Sparkline values={nwSeries} width={320} height={48} color="var(--primary)" fillOpacity={0.1} />
          </div>
        )}
      </div>

      <div className="px-5 pb-[120px] md:hidden">
        <AccountGroupAccordion groups={groupedAccounts} balanceOf={balanceOf} fmt={fmt} defaultOpen={DEFAULT_OPEN_GROUPS} onAddAccount={openCreate} />
      </div>

      <div className="hidden px-8 pb-12 md:block">
        <div className="grid grid-cols-1 items-start gap-8 md:grid-cols-[1.7fr_1fr]">
          <div className="min-w-0">
            <AccountGroupAccordion groups={groupedAccounts} balanceOf={balanceOf} fmt={fmt} defaultOpen={DEFAULT_OPEN_GROUPS} onAddAccount={openCreate} />
          </div>

          <aside className="min-w-0">
            <div className="mb-3 font-serif text-lg italic">Recent activity</div>
            <div className="bg-card border-border overflow-hidden rounded-xl border">
              {[...ledgerTxns]
                .sort((a, b) => b.date.localeCompare(a.date))
                .slice(0, 8)
                .map((t, i) => {
                  const cat = catById(t.category);
                  const inc = t.amount > 0;
                  return (
                    <button
                      key={t.id}
                      type="button"
                      onClick={() => openTransaction(t.id)}
                      className={cn('hover:bg-secondary/40 flex w-full items-center gap-3 px-4 py-3 text-left text-inherit', i && 'border-border border-t-[0.5px]')}
                    >
                      <CatBar hue={cat.hue} />
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-sm font-medium">{t.merchant}</div>
                        <div className="text-muted-foreground text-xs">{t.date.slice(5).replace('-', '/')} · {cat.name}</div>
                      </div>
                      <Money value={t.amount} signed={inc} className={cn('shrink-0 font-mono text-[13px] font-semibold', inc ? 'text-success' : 'text-foreground')} />
                    </button>
                  );
                })}
            </div>
          </aside>
        </div>
      </div>
      {createDialog}
    </MobilePage>
  );
}
