'use client';

import { useParams } from 'next/navigation';
import Link from 'next/link';
import { Icon, Money, Sparkline, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { useCurrency } from '@/components/currency-provider';
import { MOCK, fmtMoneyShort, catById } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';

export default function AccountDetailPage() {
  const { currency } = useCurrency();
  const params = useParams();
  const accountId = params.id as string;
  const account = MOCK.accounts.find(a => a.id === accountId) || MOCK.accounts[0];
  const txs = useFinanceStore((s) => s.transactions).filter(t => t.account === account.id);

  return (
    <MobilePage
      header={
        <ScreenHeader
          title={account.name}
          back={true}
        />
      }
    >
      <div className="px-5 pb-[22px]">
        <div className="text-muted-foreground mb-[18px] flex items-center gap-2 text-xs">
          <Link href="/accounts" className="text-muted-foreground no-underline">Accounts</Link>
          <Icon name="chev" size={11}/>
          <span className="text-foreground">{account.name}</span>
        </div>

        <div className="relative mb-6 grid grid-cols-2 gap-8 overflow-hidden rounded-2xl p-7 text-white" style={{ background: account.color }}>
          <div className="absolute -top-[60px] -right-20 size-60 rounded-full bg-white/5"/>
          <div>
            <div className="mb-1.5 text-[11px] uppercase tracking-[1px] opacity-65">Available balance</div>
            <div className="font-serif text-[56px] leading-none -tracking-[2px]">
              <Money value={account.balance} mono={false} className="font-serif"/>
            </div>
            <div className="mt-[22px] flex gap-5">
              <div><div className="mb-[3px] text-[10px] tracking-[1px] opacity-60">IN · 30D</div><div className="font-serif text-[22px]">{fmtMoneyShort(5800, currency)}</div></div>
              <div><div className="mb-[3px] text-[10px] tracking-[1px] opacity-60">OUT · 30D</div><div className="font-serif text-[22px]">{fmtMoneyShort(1850, currency)}</div></div>
              <div><div className="mb-[3px] text-[10px] tracking-[1px] opacity-60">NET</div><div className="font-serif text-[22px]" style={{ color: '#9bb89b' }}>+{fmtMoneyShort(3950, currency)}</div></div>
            </div>
          </div>
          <div className="relative flex flex-col justify-end">
            <Sparkline values={[3200,3400,3300,3700,3650,4100,4050,4300,4250,4400,4500,4450,4218]} width={420} height={120} color="#fff" stroke={1.8} fillOpacity={0.16}/>
          </div>
        </div>

        <div className="grid grid-cols-[2fr_1fr] gap-4">
          <div className="bg-card border-border overflow-hidden rounded-[14px] border">
            <div className="border-border flex items-center justify-between border-b px-[18px] py-3.5">
              <div className="text-sm font-semibold">All transactions · {txs.length}</div>
              <div className="text-muted-foreground flex cursor-pointer items-center gap-1 text-xs"><Icon name="filter" size={12}/>Filter</div>
            </div>
            {txs.slice(0, 6).map((tx, i) => {
              const cat = catById(tx.category);
              const inc = tx.amount > 0;
              return (
                <div key={tx.id} className={cn('flex cursor-pointer items-center gap-3 px-[18px] py-3', i && 'border-border border-t-[0.5px]')}>
                  <MerchantGlyph name={tx.merchant} size={32} hue={cat.hue}/>
                  <div className="flex-1">
                    <div className="text-[13px] font-medium">{tx.merchant}</div>
                    <div className="text-muted-foreground mt-0.5 text-[11px]">{tx.date.slice(5).replace('-','/')} · {cat.name || 'Income'}</div>
                  </div>
                  <Money value={tx.amount} signed={inc} className={cn('font-mono text-[13px] font-semibold', inc ? 'text-success' : 'text-foreground')}/>
                </div>
              );
            })}
          </div>

          <div className="bg-card border-border rounded-[14px] border p-[18px]">
            <div className="text-muted-foreground mb-2.5 font-mono text-[10px] tracking-[1.2px]">ACCOUNT DETAILS</div>
            {[
              ['Type', account.type.charAt(0).toUpperCase() + account.type.slice(1)],
              ['Number', `•••• ${account.last4}`],
              ['Routing', '021000021'],
              ['Institution', 'Chase Bank, N.A.'],
              ['Currency', currency],
              ['Last sync', '2 min ago'],
              ['Linked since', 'Jan 2024'],
            ].map(([l, v], i) => (
              <div key={l} className={cn('flex justify-between py-2 text-xs', i && 'border-border border-t-[0.5px] border-dotted')}>
                <span className="text-muted-foreground">{l}</span>
                <span className="font-mono">{v}</span>
              </div>
            ))}
            <div className="bg-secondary text-secondary-foreground mt-3.5 flex items-center gap-2 rounded-lg px-3.5 py-2.5 text-xs">
              <Icon name="sync" size={12}/>Auto-categorize: on
            </div>
          </div>
        </div>
      </div>
    </MobilePage>
  );
}
