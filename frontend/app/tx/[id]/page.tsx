'use client';

import { useParams } from 'next/navigation';
import { useTweaks } from '@/components/TweaksContext';
import { Icon, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader } from '@/components/MobileComponents';
import { MOCK, catById, acctById, fmtMoney } from '@/lib/data';

export default function TxDetailPage() {
  const { theme: th } = useTweaks();
  const params = useParams();
  const txId = params.id as string;
  const tx = MOCK.transactions.find(t => t.id === txId) || MOCK.transactions[1];
  const cat = catById(tx.category);
  const acct = acctById(tx.account);
  const when = new Date(`${tx.date}T${tx.time ?? '00:00'}`);
  const whenStr = `${when.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })} · ${when.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}`;
  const acctLabel = acct.last4 ? `${acct.name} · ${acct.last4}` : acct.name;

  return (
    <div style={{ padding: '0 20px 120px' }}>
      <ScreenHeader title="" back={true} trailing={<div style={{ width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer' }}><Icon name="dots" size={16}/></div>}/>

      <div style={{ padding: '0 24px 28px', textAlign: 'center' }}>
        <MerchantGlyph name={tx.merchant} size={64} hue={cat.hue}/>
        <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 22, color: th.muted, marginTop: 18 }}>You spent at</div>
        <div style={{ fontFamily: th.display, fontSize: 34, letterSpacing: -0.8, lineHeight: 1, marginTop: 4 }}>{tx.merchant}</div>
        <div style={{ fontFamily: th.display, fontSize: 56, letterSpacing: -2, marginTop: 18, fontWeight: 400 }}>
          {fmtMoney(Math.abs(tx.amount), th.currency)}
        </div>
        <div style={{ fontSize: 12, color: th.muted, marginTop: 6 }}>{whenStr} · {acct.name}</div>
      </div>

      <div style={{ display: 'flex', gap: 8, padding: '0 0 22px' }}>
        {['split', 'tag', 'sync', 'cam'].map((a) => (
          <div key={a} style={{ flex: 1, height: 60, borderRadius: 12, border: `1px solid ${th.line}`, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, color: th.ink, cursor: 'pointer' }}>
            <Icon name={a} size={18}/>
            <span style={{ fontSize: 10, fontWeight: 500 }}>{a === 'split' ? 'Split' : a === 'tag' ? 'Tag' : a === 'sync' ? 'Recurring' : 'Receipt'}</span>
          </div>
        ))}
      </div>

      <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: '4px 16px' }}>
        {[
          { l: 'Category', v: cat.name },
          { l: 'Account', v: acctLabel },
          { l: 'Status', v: tx.pending ? 'Pending' : 'Posted' },
          { l: 'Note', v: tx.note || '—' },
          { l: 'Transaction', v: 'AMX-9F2B-44A1' },
        ].map((r, i) => (
          <div key={r.l} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 0', borderTop: i ? `0.5px solid ${th.line}` : 'none', fontSize: 13 }}>
            <span style={{ color: th.muted }}>{r.l}</span>
            <span>{r.v}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
