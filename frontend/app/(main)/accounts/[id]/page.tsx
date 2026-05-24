'use client';

import { useParams } from 'next/navigation';
import Link from 'next/link';
import { useTweaks } from '@/components/TweaksContext';
import { Icon, Money, Sparkline, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { MOCK, fmtMoneyShort, catById } from '@/lib/data';

export default function AccountDetailPage() {
  const { theme: th } = useTweaks();
  const params = useParams();
  const accountId = params.id as string;
  const account = MOCK.accounts.find(a => a.id === accountId) || MOCK.accounts[0];
  const txs = MOCK.transactions.filter(t => t.account === account.id);

  return (
    <MobilePage
      header={
        <ScreenHeader
          title={account.name}
          back={true}
        />
      }
    >
      <div style={{ padding: '0 20px 22px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: th.muted, marginBottom: 18 }}>
          <Link href="/accounts" style={{ color: th.muted, textDecoration: 'none' }}>Accounts</Link>
          <Icon name="chev" size={11}/>
          <span style={{ color: th.ink }}>{account.name}</span>
        </div>

        <div style={{ background: account.color, color: '#fff', borderRadius: 16, padding: 28, marginBottom: 24, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 32, position: 'relative', overflow: 'hidden' }}>
          <div style={{ position: 'absolute', top: -60, right: -80, width: 240, height: 240, borderRadius: 120, background: 'rgba(255,255,255,0.05)' }}/>
          <div>
            <div style={{ fontSize: 11, opacity: 0.65, letterSpacing: 1, textTransform: 'uppercase', marginBottom: 6 }}>Available balance</div>
            <div style={{ fontFamily: th.display, fontSize: 56, letterSpacing: -2, lineHeight: 1 }}>
              <Money value={account.balance} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
            </div>
            <div style={{ display: 'flex', gap: 20, marginTop: 22 }}>
              <div><div style={{ fontSize: 10, opacity: 0.6, letterSpacing: 1, marginBottom: 3 }}>IN · 30D</div><div style={{ fontFamily: th.display, fontSize: 22 }}>{fmtMoneyShort(5800, th.currency)}</div></div>
              <div><div style={{ fontSize: 10, opacity: 0.6, letterSpacing: 1, marginBottom: 3 }}>OUT · 30D</div><div style={{ fontFamily: th.display, fontSize: 22 }}>{fmtMoneyShort(1850, th.currency)}</div></div>
              <div><div style={{ fontSize: 10, opacity: 0.6, letterSpacing: 1, marginBottom: 3 }}>NET</div><div style={{ fontFamily: th.display, fontSize: 22, color: '#9bb89b' }}>+{fmtMoneyShort(3950, th.currency)}</div></div>
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', position: 'relative' }}>
            <Sparkline values={[3200,3400,3300,3700,3650,4100,4050,4300,4250,4400,4500,4450,4218]} width={420} height={120} color="#fff" stroke={1.8} fillOpacity={0.16}/>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 16 }}>
          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
            <div style={{ padding: '14px 18px', borderBottom: `1px solid ${th.line}`, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ fontSize: 14, fontWeight: 600 }}>All transactions · {txs.length}</div>
              <div style={{ fontSize: 12, color: th.muted, display: 'flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}><Icon name="filter" size={12}/>Filter</div>
            </div>
            {txs.slice(0, 6).map((tx, i) => {
              const cat = catById(tx.category);
              const inc = tx.amount > 0;
              return (
                <div key={tx.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 18px', borderTop: i ? `0.5px solid ${th.line}` : 'none', cursor: 'pointer' }}>
                  <MerchantGlyph name={tx.merchant} size={32} hue={cat.hue}/>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 13, fontWeight: 500 }}>{tx.merchant}</div>
                    <div style={{ fontSize: 11, color: th.muted, marginTop: 2 }}>{tx.date.slice(5).replace('-','/')} · {cat.name || 'Income'}</div>
                  </div>
                  <Money value={tx.amount} currency={th.currency} signed={inc} style={{ fontFamily: th.mono, fontSize: 13, fontWeight: 600, color: inc ? th.pos : th.ink }}/>
                </div>
              );
            })}
          </div>

          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 18 }}>
            <div style={{ fontFamily: th.mono, fontSize: 10, letterSpacing: 1.2, color: th.muted, marginBottom: 10 }}>ACCOUNT DETAILS</div>
            {[
              ['Type', account.type.charAt(0).toUpperCase() + account.type.slice(1)],
              ['Number', `•••• ${account.last4}`],
              ['Routing', '021000021'],
              ['Institution', 'Chase Bank, N.A.'],
              ['Currency', th.currency],
              ['Last sync', '2 min ago'],
              ['Linked since', 'Jan 2024'],
            ].map(([l, v], i) => (
              <div key={l} style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 0', borderTop: i ? `0.5px dotted ${th.line}` : 'none', fontSize: 12 }}>
                <span style={{ color: th.muted }}>{l}</span>
                <span style={{ fontFamily: th.mono }}>{v}</span>
              </div>
            ))}
            <div style={{ marginTop: 14, padding: '10px 14px', background: th.paperAlt, borderRadius: 8, fontSize: 12, color: th.ink2, display: 'flex', alignItems: 'center', gap: 8 }}>
              <Icon name="sync" size={12}/>Auto-categorize: on
            </div>
          </div>
        </div>
      </div>
    </MobilePage>
  );
}