'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Icon, Money, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { Accordion, AccordionItem, AccordionTrigger, AccordionContent } from '@/components/ui/accordion';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useTransactionSheet } from '@/components/transaction-sheet';
import { useDb } from '@/components/db-provider';
import { listAccounts } from '@/lib/db/queries/accounts';
import { useFinanceStore } from '@/lib/store';
import { MOCK, catById } from '@/lib/data';
import { accountBalance } from '@/lib/derive';
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
}: {
  groups: GroupWithAccounts[];
  balanceOf: (id: string) => number;
  fmt: (n: number) => string;
  defaultOpen: string[];
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
                <button type="button" className="border-border text-muted-foreground flex h-[52px] w-full cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed text-xs">
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
                </div>
              )}
            </AccordionContent>
          </AccordionItem>
        );
      })}
    </Accordion>
  );
}

export default function AccountsPage() {
  const { fmt } = useMoney();
  const { active, activeId } = useLedger();
  const { openTransaction } = useTransactionSheet();
  const { exec, version } = useDb();
  const allTxns = useFinanceStore((s) => s.transactions);
  const accountOverrides = useFinanceStore((s) => s.accountOverrides);
  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === activeId);

  // Account balances come from the live DB; fall back to the derived figure
  // (baseline + delta) until the DB is ready. Both yield the same number.
  const [balById, setBalById] = useState<Record<string, number> | null>(null);
  useEffect(() => {
    if (!exec) return;
    let cancelled = false;
    listAccounts(exec, activeId)
      .then((accts) => {
        if (cancelled) return;
        const m: Record<string, number> = {};
        for (const a of accts) m[a.id] = a.balance;
        setBalById(m);
      })
      .catch((err) => console.error('Could not load account balances from DB', err));
    return () => {
      cancelled = true;
    };
  }, [exec, version, activeId]);
  const balanceOf = (id: string) => balById?.[id] ?? accountBalance(ledgerTxns, id);

  const ledgerAccounts = MOCK.accounts
    .filter((a) => ((a as { ledger?: string }).ledger ?? 'personal') === activeId)
    .map((a) => {
      const ov = accountOverrides[a.id];
      return ov ? { ...a, name: ov.name || a.name, last4: ov.last4 || a.last4 } : a;
    });

  if (ledgerAccounts.length === 0) {
    return (
      <MobilePage>
        <ScreenHeader title="Accounts" trailing={<IconButton icon="search" aria-label="Search" />} />
        <div className="text-muted-foreground px-5 pt-16 text-center text-sm">
          No accounts linked in <span className="text-foreground font-medium">{active.name}</span> yet.
        </div>
      </MobilePage>
    );
  }

  const total = ledgerAccounts.reduce((s, a) => s + balanceOf(a.id), 0);
  const groupedAccounts = MOCK.accountGroups.map((g) => ({
    ...g,
    accounts: ledgerAccounts.filter((a) => a.group === g.id),
  }));

  return (
    <MobilePage>
      <ScreenHeader title="Accounts" trailing={<IconButton icon="search" aria-label="Search" />} />

      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Net worth · all accounts"
          value={<Money value={total} mono={false} className="font-serif" />}
          sublabel={<span className="text-success">+ <Money value={812} /> this month</span>}
        />
      </div>

      <div className="px-5 pb-[120px] md:hidden">
        <AccountGroupAccordion groups={groupedAccounts} balanceOf={balanceOf} fmt={fmt} defaultOpen={DEFAULT_OPEN_GROUPS} />
      </div>

      <div className="hidden px-8 pb-12 md:block">
        <div className="grid grid-cols-1 items-start gap-8 md:grid-cols-[1.7fr_1fr]">
          <div className="min-w-0">
            <AccountGroupAccordion groups={groupedAccounts} balanceOf={balanceOf} fmt={fmt} defaultOpen={DEFAULT_OPEN_GROUPS} />
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
                      <MerchantGlyph name={t.merchant} hue={cat.hue} size={30} />
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
    </MobilePage>
  );
}
