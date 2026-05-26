'use client';

import Link from 'next/link';
import { Icon, Money, Sparkline, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { Accordion, AccordionItem, AccordionTrigger, AccordionContent } from '@/components/ui/accordion';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useFinanceStore } from '@/lib/store';
import { MOCK, catById, acctById } from '@/lib/data';
import { accountBalance } from '@/lib/derive';
import { cn } from '@/lib/utils';

const DEFAULT_OPEN_GROUPS = ['cash', 'credit', 'invest'];

export default function AccountsPage() {
  const { fmt } = useMoney();
  const { active, activeId } = useLedger();
  const allTxns = useFinanceStore((s) => s.transactions);
  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === activeId);

  const ledgerAccounts = MOCK.accounts.filter(
    (a) => ((a as { ledger?: string }).ledger ?? 'personal') === activeId,
  );

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

  const total = ledgerAccounts.reduce((s, a) => s + accountBalance(ledgerTxns, a.id), 0);
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
        <Accordion type="multiple" defaultValue={DEFAULT_OPEN_GROUPS}>
          {groupedAccounts.map((g) => {
            const groupTotal = g.accounts.reduce((s, a) => s + accountBalance(ledgerTxns, a.id), 0);
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
                        const bal = accountBalance(ledgerTxns, a.id);
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
      </div>

      <div className="hidden px-8 pb-12 md:block">
        <div className="flex flex-col gap-9">
          {groupedAccounts.map((g) => {
            if (g.accounts.length === 0) return null;
            const groupTotal = g.accounts.reduce((s, a) => s + accountBalance(ledgerTxns, a.id), 0);
            return (
              <section key={g.id}>
                <div className="border-border mb-4 flex items-baseline justify-between border-b pb-2.5">
                  <div className="flex items-baseline gap-2.5">
                    <h2 className="font-serif text-xl italic -tracking-[0.3px]">{g.name}</h2>
                    <span className="text-muted-foreground font-mono text-[11px]">{g.accounts.length}</span>
                  </div>
                  <span className="text-foreground font-mono text-sm tabular-nums">
                    {groupTotal < 0 ? '−' : ''}{fmt(Math.abs(groupTotal))}
                  </span>
                </div>
                <div className="grid grid-cols-2 gap-4 xl:grid-cols-3">
                  {g.accounts.map((a) => {
                    const bal = accountBalance(ledgerTxns, a.id);
                    return (
                      <div key={a.id} className="relative overflow-hidden rounded-2xl p-5 text-white" style={{ background: a.color }}>
                        <div className="absolute -top-10 -right-10 size-32 rounded-full bg-white/5" />
                        <div className="flex items-start justify-between">
                          <div>
                            <div className="text-sm font-medium">{a.name}</div>
                            <div className="mt-0.5 font-mono text-[10px] opacity-60">•••• {a.last4}</div>
                          </div>
                          <Link href={`/accounts/${a.id}`} aria-label={`Open ${a.name}`} className="opacity-70 hover:opacity-100">
                            <Icon name="arrow-ur" size={16} />
                          </Link>
                        </div>
                        <div className="mt-6 font-serif text-3xl -tracking-[1px]">
                          <Money value={bal} mono={false} className="font-serif" />
                        </div>
                        <div className="-mx-1 mt-2 opacity-80">
                          <Sparkline values={[30, 42, 38, 50, 46, 58, 54, 62, 60, 68]} width={300} height={34} color="#fff" stroke={1.5} fillOpacity={0.14} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              </section>
            );
          })}
        </div>

        <div className="mt-9">
          <div className="mb-3 font-serif text-lg italic">Recent activity</div>
          <div className="bg-card border-border overflow-hidden rounded-xl border">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-muted-foreground border-border border-b text-left text-[11px] tracking-wide uppercase">
                  <th className="px-4 py-2.5 font-medium">Date</th>
                  <th className="px-4 py-2.5 font-medium">Merchant</th>
                  <th className="px-4 py-2.5 font-medium">Category</th>
                  <th className="px-4 py-2.5 font-medium">Account</th>
                  <th className="px-4 py-2.5 text-right font-medium">Amount</th>
                </tr>
              </thead>
              <tbody>
                {[...ledgerTxns]
                  .sort((a, b) => b.date.localeCompare(a.date))
                  .slice(0, 8)
                  .map((t) => {
                    const cat = catById(t.category);
                    return (
                      <tr key={t.id} className="border-border hover:bg-secondary/40 border-t first:border-t-0">
                        <td className="text-muted-foreground px-4 py-2.5 font-mono text-xs whitespace-nowrap">
                          {t.date.slice(5).replace('-', '/')}
                        </td>
                        <td className="px-4 py-2.5">
                          <Link href={`/tx/${t.id}`} className="flex items-center gap-2.5">
                            <MerchantGlyph name={t.merchant} hue={cat.hue} size={26} />
                            {t.merchant}
                          </Link>
                        </td>
                        <td className="text-muted-foreground px-4 py-2.5">{cat.name}</td>
                        <td className="text-muted-foreground px-4 py-2.5">{acctById(t.account).name}</td>
                        <td className={cn('px-4 py-2.5 text-right font-mono', t.amount > 0 ? 'text-success' : 'text-foreground')}>
                          <Money value={t.amount} signed={t.amount > 0} />
                        </td>
                      </tr>
                    );
                  })}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </MobilePage>
  );
}
