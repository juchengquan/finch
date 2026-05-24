'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon, StackedBar } from '@/components/primitives';
import { SchemaChip, ScreenHeader, IconButton } from '@/components/MobileComponents';
import { LEDGER } from '@/lib/data';
import { LedgerMobilePage } from '@/components/LedgerMobilePage';

export default function RecurringPage() {
  const { theme: th } = useTweaks();
  const t = LEDGER.recurringTemplates[0];

  return (
    <LedgerMobilePage
      header={
        <ScreenHeader
          title="Recurring"
          trailing={<IconButton icon="dots"/>}
        />
      }
    >
      <div style={{ padding: '0 20px 120px' }}>
        <div style={{ padding: '0 4px 22px' }}>
          <SchemaChip label="recurring_templates"/>
          <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -0.8, lineHeight: 1.1, marginTop: 10 }}>
            <span style={{ fontStyle: 'italic', color: th.muted }}>Every 25th, you receive</span><br/>
            <span style={{ fontSize: 44 }}>S$5,800.00</span>
          </div>
          <div style={{ fontSize: 12, color: th.muted, marginTop: 8 }}>
            from <b style={{ color: th.ink2 }}>Acme</b> — next on May 25 · awaits your confirmation
          </div>
        </div>

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8, padding: '0 4px' }}>
          <div style={{ fontFamily: th.display, fontSize: 20, fontStyle: 'italic', letterSpacing: -0.2 }}>Splits</div>
          <SchemaChip label="recurring_splits"/>
        </div>
        <div style={{ fontSize: 12, color: th.muted, padding: '0 4px 10px' }}>
          Salary is split across accounts. Total must equal 100%.
        </div>

        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 14, marginBottom: 10 }}>
          <StackedBar
            slices={(t.splits || []).map((s, i) => ({ value: s.pct || 0, color: i === 0 ? th.accent : i === 1 ? th.warn : th.pos }))}
            width={310} height={12} radius={6}/>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 10, fontFamily: th.mono, fontSize: 10, color: th.muted }}>
            <span>0%</span><span>50%</span><span>100%</span>
          </div>
        </div>

        {(t.splits || []).map((s, i) => {
          const dot = i === 0 ? th.accent : i === 1 ? th.warn : th.pos;
          const amount = 5800 * s.pct / 100;
          return (
            <div key={i} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 14, marginBottom: 8 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={{ width: 8, height: 36, borderRadius: 4, background: dot }}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                    <div style={{ fontSize: 14, fontWeight: 500 }}>{s.account}</div>
                    <div style={{ fontFamily: th.body, fontSize: 14, fontWeight: 500 }}>S${amount.toLocaleString(undefined, { maximumFractionDigits: 0 })}</div>
                  </div>
                  <div style={{ fontSize: 11, color: th.muted, marginTop: 2 }}>{s.label} · <span style={{ fontFamily: th.mono, fontSize: 10 }}>amount_pct = {s.pct}</span></div>
                </div>
              </div>
            </div>
          );
        })}

        <div style={{
          marginTop: 4, height: 44, borderRadius: 12, border: `1px dashed ${th.line}`,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: th.muted, fontSize: 12, cursor: 'pointer'
        }}>
          <Icon name="plus" size={14}/>Add split rule
        </div>

        <div style={{ padding: '24px 0 8px' }}>
          <div style={{
            height: 50, borderRadius: 25, background: th.ink, color: th.paper,
            display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 500, cursor: 'pointer'
          }}>
            Save template
          </div>
        </div>
      </div>
    </LedgerMobilePage>
  );
}