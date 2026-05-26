'use client';

import Link from 'next/link';
import { Icon, Money } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { Accordion, AccordionItem, AccordionTrigger, AccordionContent } from '@/components/ui/accordion';
import { useCurrency } from '@/components/currency-provider';
import { MOCK, fmtMoneyShort } from '@/lib/data';
import { cn } from '@/lib/utils';

const DEFAULT_OPEN_GROUPS = ['cash', 'credit', 'invest'];

export default function AccountsPage() {
  const { currency } = useCurrency();
  const total = MOCK.accounts.reduce((s, a) => s + a.balance, 0);

  const groupedAccounts = MOCK.accountGroups.map((g) => ({ ...g, accounts: MOCK.accounts.filter((a) => a.group === g.id) }));

  return (
    <MobilePage>
      <ScreenHeader
        title="Accounts"
        trailing={<IconButton icon="search" aria-label="Search"/>}
      />

      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Net worth · all accounts"
          value={<Money value={total} mono={false} className="font-serif"/>}
          sublabel={<span className="text-success">+ <Money value={812}/> this month</span>}
        />
      </div>

      <div className="px-5 pb-[120px]">
        <Accordion type="multiple" defaultValue={DEFAULT_OPEN_GROUPS}>
          {groupedAccounts.map((g) => {
            const groupTotal = g.accounts.reduce((s: number, a: typeof MOCK.accounts[0]) => s + a.balance, 0);
            const empty = g.accounts.length === 0;

            return (
              <AccordionItem key={g.id} value={g.id}>
                <AccordionTrigger>
                  <div className="flex items-center gap-2.5">
                    <div className="flex-1 font-serif text-lg italic -tracking-[0.2px]">{g.name}</div>
                    <span className={cn('font-mono text-[11px] tracking-[0.3px]', empty ? 'text-muted-foreground' : 'text-secondary-foreground')}>
                      {empty ? '—' : `${g.accounts.length} · ${groupTotal < 0 ? '−' : ''}${fmtMoneyShort(groupTotal, currency)}`}
                    </span>
                  </div>
                </AccordionTrigger>
                <AccordionContent>
                  {empty ? (
                    <button type="button" className="border-border text-muted-foreground flex h-[52px] w-full cursor-pointer items-center justify-center gap-2 rounded-xl border border-dashed text-xs">
                      <Icon name="plus" size={14}/>Add account
                    </button>
                  ) : (
                    <div className="bg-card border-border rounded-xl border">
                      {g.accounts.map((a, i) => (
                        <Link key={a.id} href={`/accounts/${a.id}`} className={cn('flex cursor-pointer items-center gap-3 p-3.5 text-inherit no-underline', i && 'border-border border-t-[0.5px]')}>
                          <div className="flex size-[38px] shrink-0 items-center justify-center rounded-lg font-mono text-[10px] font-semibold tracking-[0.5px] text-white" style={{ background: a.color }}>{a.last4.slice(-2)}</div>
                          <div className="min-w-0 flex-1">
                            <div className="text-sm font-medium">{a.name}</div>
                            <div className="text-muted-foreground mt-0.5 font-mono text-[10px] tracking-[0.5px]">•••• {a.last4}</div>
                          </div>
                          <div className="flex items-center gap-2.5">
                            <div className="min-w-[70px] text-right">
                              <div className={cn('font-sans text-base font-medium leading-none tabular-nums', a.balance < 0 ? 'text-destructive' : 'text-foreground')}>
                                {a.balance < 0 ? '−' : ''}{fmtMoneyShort(Math.abs(a.balance), currency)}
                              </div>
                            </div>
                            <Icon name="chev" size={12} className="text-muted-foreground shrink-0"/>
                          </div>
                        </Link>
                      ))}
                    </div>
                  )}
                </AccordionContent>
              </AccordionItem>
            );
          })}
        </Accordion>
      </div>
    </MobilePage>
  );
}
