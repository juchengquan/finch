'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';
import { LedgerMobilePage } from '@/components/LedgerMobilePage';

export default function MerchantsPage() {
  const { theme: th } = useTweaks();

  return (
    <LedgerMobilePage
      header={
        <ScreenHeader
          title="Merchants"
          trailing={<IconButton icon="plus"/>}
        />
      }
    >
      <div style={{ padding: '0 20px 120px' }}>
        <div style={{ padding: '0 4px 18px' }}>
          <SchemaChip label="counterparties"/>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 14, marginTop: 8 }}>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 40, letterSpacing: -1.4, lineHeight: 1 }}>{LEDGER.counterparties.length}</div>
              <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginTop: 4 }}>STANDARDISED</div>
            </div>
            <div style={{ width: 1, height: 32, background: th.line }}/>
            <div>
              <div style={{ fontFamily: th.display, fontSize: 40, letterSpacing: -1.4, lineHeight: 1, color: th.warn }}>
                {LEDGER.counterparties.filter(c => !c.verified).length}
              </div>
              <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1, marginTop: 4 }}>UNVERIFIED</div>
            </div>
          </div>
        </div>

        <div style={{ margin: '0 0 14px', height: 38, borderRadius: 19, background: th.paperAlt, display: 'flex', alignItems: 'center', gap: 10, padding: '0 14px', color: th.muted, fontSize: 13 }}>
          <Icon name="search" size={14}/>Search merchants & aliases…
        </div>

        <div style={{ display: 'flex', flexDirection: 'column' }}>
          {LEDGER.counterparties.map((c, i) => (
            <div key={c.id} style={{
              display: 'flex', alignItems: 'flex-start', gap: 12,
              padding: '14px 0', borderTop: i ? `0.5px solid ${th.line}` : 'none'
            }}>
              <div style={{ width: 40, height: 40, borderRadius: 8, background: `oklch(0.65 0.2 ${c.hue})`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.mono, fontSize: 10, fontWeight: 600, color: '#fff', flexShrink: 0 }}>
                {c.name.slice(0, 2).toUpperCase()}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 8 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <div style={{ fontSize: 14, fontWeight: 500 }}>{c.name}</div>
                    {!c.verified && (
                      <span style={{
                        fontFamily: th.mono, fontSize: 9, color: th.warn, letterSpacing: 0.6,
                        padding: '2px 6px', border: `1px solid ${th.warn}66`, borderRadius: 4
                      }}>UNVERIFIED</span>
                    )}
                  </div>
                  <div style={{ fontFamily: th.mono, fontSize: 11, color: th.muted }}>{c.txCount}×</div>
                </div>
                <div style={{ fontSize: 11, color: th.muted, marginTop: 4 }}>
                  {c.category} <span style={{ margin: '0 5px' }}>·</span>
                  <span style={{ fontFamily: th.mono, fontSize: 10, color: th.ink2 }}>aliases:</span>
                </div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginTop: 6 }}>
                  {c.aliases.map((a) => (
                    <span key={a} style={{
                      fontFamily: th.mono, fontSize: 10, padding: '2px 7px', background: th.paperAlt,
                      color: th.ink2, borderRadius: 4, letterSpacing: 0.2
                    }}>{a}</span>
                  ))}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </LedgerMobilePage>
  );
}