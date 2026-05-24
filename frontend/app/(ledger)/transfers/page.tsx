'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';
import { LedgerMobilePage } from '@/components/LedgerMobilePage';

export default function TransfersPage() {
  const { theme: th } = useTweaks();
  const tg = LEDGER.transferGroups[1];

  return (
    <LedgerMobilePage
      header={
        <ScreenHeader
          title="Transfers"
          trailing={<IconButton icon="dots"/>}
        />
      }
    >
      <div style={{ padding: '0 20px 120px' }}>
        <div style={{ padding: '0 4px 22px', textAlign: 'center' }}>
          <SchemaChip label="transfer_groups"/>
          <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 22, color: th.muted, marginTop: 14 }}>You transferred</div>
          <div style={{ fontFamily: th.display, fontSize: 52, letterSpacing: -1.8, marginTop: 4 }}>
            S$80,000<span style={{ fontSize: 28, color: th.muted, letterSpacing: -0.5 }}>.00</span>
          </div>
          <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 18, color: th.ink2, marginTop: 2 }}>
            → ¥422,728 received
          </div>
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 8, marginTop: 14,
            padding: '6px 12px', borderRadius: 14, background: th.paperAlt,
            fontFamily: th.mono, fontSize: 10, letterSpacing: 0.6, color: th.ink2
          }}>
            <Icon name="check" size={12} style={{ color: th.pos }} stroke={2}/>
            RATE LOCKED @ 5.2841 · MON MAY 18
          </div>
        </div>

        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, marginBottom: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 16, borderBottom: `1px dashed ${th.line}` }}>
            <div style={{
              width: 32, height: 32, borderRadius: 16, background: `${th.neg}1a`, color: th.neg,
              display: 'flex', alignItems: 'center', justifyContent: 'center'
            }}>
              <Icon name="arrow-u" size={16} stroke={2}/>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1 }}>FROM · PERSONAL LEDGER</div>
              <div style={{ fontSize: 14, fontWeight: 500, marginTop: 2 }}>{tg.fromAccount}</div>
            </div>
            <div style={{ fontFamily: th.body, fontSize: 16, fontWeight: 500, color: th.neg, fontVariantNumeric: 'tabular-nums' }}>−S$80,000.00</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 16 }}>
            <div style={{
              width: 32, height: 32, borderRadius: 16, background: `${th.pos}1a`, color: th.pos,
              display: 'flex', alignItems: 'center', justifyContent: 'center'
            }}>
              <Icon name="arrow-d" size={16} stroke={2}/>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: th.mono, fontSize: 9, color: th.muted, letterSpacing: 1 }}>TO · SIDE STUDIO LEDGER</div>
              <div style={{ fontSize: 14, fontWeight: 500, marginTop: 2 }}>{tg.toAccount}</div>
            </div>
            <div style={{ fontFamily: th.body, fontSize: 16, fontWeight: 500, color: th.pos, fontVariantNumeric: 'tabular-nums' }}>+¥422,728</div>
          </div>
        </div>

        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: '4px 16px' }}>
          {[
            ['transfer_group_id', tg.id],
            ['amount_base',       'S$80,000.00 (locked)'],
            ['exchange_rate',     '5.2841 SGD→CNY'],
            ['from_currency',    'SGD'],
            ['to_currency',       'CNY'],
            ['notes',             tg.notes],
          ].map((r, i) => (
            <div key={r[0]} style={{
              display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '12px 0',
              borderTop: i ? `0.5px solid ${th.line}` : 'none', fontSize: 13
            }}>
              <span style={{ fontFamily: th.mono, fontSize: 11, color: th.muted, letterSpacing: 0.4 }}>{r[0]}</span>
              <span style={{ textAlign: 'right' }}>{r[1]}</span>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 14, fontSize: 11, color: th.muted, lineHeight: 1.5, padding: '0 4px' }}>
          The exchange rate is locked at import time. Both transactions share <span style={{ fontFamily: th.mono, color: th.ink2 }}>amount_base</span> so reports across ledgers stay consistent.
        </div>
      </div>
    </LedgerMobilePage>
  );
}