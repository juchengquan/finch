'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton, MobilePage } from '@/components/MobileComponents';
import { LEDGER, fmtNative } from '@/lib/data';

export default function PendingPage() {
  const { theme: th } = useTweaks();

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Pending"
          trailing={<IconButton icon="filter"/>}
        />
      }
    >
      <div style={{ padding: '0 20px 120px' }}>
        <div style={{ padding: '0 4px 20px' }}>
          <SchemaChip label="status = pending"/>
          <div style={{ fontFamily: th.display, fontSize: 44, letterSpacing: -1.6, lineHeight: 1, marginTop: 6 }}>
            {LEDGER.pending.length} <span style={{ fontStyle: 'italic', color: th.muted }}>items</span>
          </div>
          <div style={{ fontSize: 13, color: th.ink2, marginTop: 6 }}>
            Confirm them to flow into your reports. Or cancel to ignore.
          </div>
        </div>

        <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
          <button type="button" style={{ flex: 1, height: 38, background: th.ink, color: th.paper, borderRadius: 19, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontSize: 12, fontWeight: 500, cursor: 'pointer', border: 'none', fontFamily: 'inherit' }}>
            <Icon name="check" size={14}/>Confirm all
          </button>
          <button type="button" aria-label="Dismiss" style={{ width: 38, height: 38, border: `1px solid ${th.line}`, borderRadius: 19, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.muted, cursor: 'pointer', background: 'none', padding: 0 }}>
            <Icon name="x" size={14}/>
          </button>
        </div>

        {LEDGER.pending.map((p, i) => {
          const inc = p.amount > 0;
          const isFx = p.currency !== 'SGD';
          return (
            <div key={p.id} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 16, marginBottom: 10 }}>
              <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                <div style={{ width: 36, height: 36, borderRadius: 8, background: `oklch(0.65 0.2 ${(i * 60) % 360})`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.mono, fontSize: 11, fontWeight: 600, color: '#fff', flexShrink: 0 }}>
                  {p.merchant.slice(0, 2).toUpperCase()}
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, alignItems: 'baseline' }}>
                    <div style={{ fontSize: 14, fontWeight: 500 }}>{p.merchant}</div>
                    <div style={{ fontFamily: th.body, fontSize: 15, fontWeight: 500, color: inc ? th.pos : th.ink, fontVariantNumeric: 'tabular-nums' }}>
                      {fmtNative(p.amount, p.currency, { signed: true })}
                    </div>
                  </div>
                  <div style={{ fontSize: 11, color: th.muted, marginTop: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
                    {p.account} · {p.date.slice(5).replace('-', '/')}
                    {isFx && <span style={{ fontFamily: th.mono, color: th.warn, fontSize: 10 }}>· FX</span>}
                  </div>
                  <div style={{
                    marginTop: 10, padding: '8px 10px', background: th.paperAlt, borderRadius: 8,
                    fontSize: 12, color: th.ink2, display: 'flex', alignItems: 'center', gap: 8
                  }}>
                    <Icon name="sparkle" size={13} style={{ color: th.accent, flexShrink: 0 }}/>{p.reason}
                  </div>
                </div>
              </div>
              <div style={{ display: 'flex', gap: 6, marginTop: 12 }}>
                <button type="button" style={{ flex: 1, height: 32, background: th.ink, color: th.paper, borderRadius: 16, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontSize: 12, fontWeight: 500, cursor: 'pointer', border: 'none', fontFamily: 'inherit' }}>
                  <Icon name="check" size={12} stroke={2}/>Confirm
                </button>
                <button type="button" style={{ height: 32, padding: '0 14px', border: `1px solid ${th.line}`, borderRadius: 16, display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: th.ink, cursor: 'pointer', background: 'none', fontFamily: 'inherit' }}>
                  Edit
                </button>
                <button type="button" aria-label="Cancel" style={{ height: 32, width: 32, border: `1px solid ${th.line}`, borderRadius: 16, display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.muted, cursor: 'pointer', background: 'none', padding: 0 }}>
                  <Icon name="x" size={12}/>
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </MobilePage>
  );
}