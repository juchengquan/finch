'use client';

import { useParams } from 'next/navigation';
import { Icon, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader } from '@/components/MobileComponents';
import { useCurrency } from '@/components/currency-provider';
import { MOCK, catById, acctById, fmtMoney } from '@/lib/data';
import { cn } from '@/lib/utils';

export default function TxDetailPage() {
  const { currency } = useCurrency();
  const params = useParams();
  const txId = params.id as string;
  const tx = MOCK.transactions.find(t => t.id === txId) || MOCK.transactions[1];
  const cat = catById(tx.category);
  const acct = acctById(tx.account);
  const when = new Date(`${tx.date}T${tx.time ?? '00:00'}`);
  const whenStr = `${when.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })} · ${when.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}`;
  const acctLabel = acct.last4 ? `${acct.name} · ${acct.last4}` : acct.name;

  return (
    <div className="px-5 pb-[120px]">
      <ScreenHeader title="" back={true} trailing={<div className="border-border text-foreground flex size-9 cursor-pointer items-center justify-center rounded-full border"><Icon name="dots" size={16}/></div>}/>

      <div className="px-6 pb-7 text-center">
        <MerchantGlyph name={tx.merchant} size={64} hue={cat.hue}/>
        <div className="text-muted-foreground mt-[18px] font-serif text-[22px] italic">You spent at</div>
        <div className="mt-1 font-serif text-[34px] leading-none -tracking-[0.8px]">{tx.merchant}</div>
        <div className="mt-[18px] font-serif text-[56px] font-normal -tracking-[2px]">
          {fmtMoney(Math.abs(tx.amount), currency)}
        </div>
        <div className="text-muted-foreground mt-1.5 text-xs">{whenStr} · {acct.name}</div>
      </div>

      <div className="flex gap-2 pb-[22px]">
        {['split', 'tag', 'sync', 'cam'].map((a) => (
          <div key={a} className="border-border text-foreground flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border">
            <Icon name={a} size={18}/>
            <span className="text-[10px] font-medium">{a === 'split' ? 'Split' : a === 'tag' ? 'Tag' : a === 'sync' ? 'Recurring' : 'Receipt'}</span>
          </div>
        ))}
      </div>

      <div className="bg-card border-border rounded-[14px] border px-4 py-1">
        {[
          { l: 'Category', v: cat.name },
          { l: 'Account', v: acctLabel },
          { l: 'Status', v: tx.pending ? 'Pending' : 'Posted' },
          { l: 'Note', v: tx.note || '—' },
          { l: 'Transaction', v: 'AMX-9F2B-44A1' },
        ].map((r, i) => (
          <div key={r.l} className={cn('flex items-center justify-between py-3 text-[13px]', i && 'border-border border-t-[0.5px]')}>
            <span className="text-muted-foreground">{r.l}</span>
            <span>{r.v}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
