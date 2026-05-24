'use client';

import { useState } from 'react';
import { useTweaks } from '@/components/TweaksContext';
import { Icon, Money, Sparkline, BarChart, MerchantGlyph, CatDot, Ring, StackedBar } from '@/components/primitives';
import { ScreenHeader, MobileTabBar, SchemaChip } from '@/components/MobileComponents';
import { MOCK, LEDGER, fmtMoney, fmtMoneyShort, catById, acctById } from '@/lib/data';

const STATUS_PAD = 60;

const LEDGER_MOBILE_TABS = [
  { id: 'pending',   icon: 'doc',   label: 'Pending' },
  { id: 'transfers', icon: 'split', label: 'Transfers' },
  { id: 'merchants', icon: 'bag',   label: 'Merchants' },
  { id: 'recurring', icon: 'sync',  label: 'Recurring' },
];

export function ScreenPendingReview() {
  const { theme: th } = useTweaks();

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <ScreenHeader title="Pending" trailing={
            <div style={{
              width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer'
            }}><Icon name="filter" size={16}/></div>
          }/>

        <div style={{ padding: '0 24px 20px' }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 4 }}>
            <SchemaChip label="status = pending"/>
            <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.6 }}>EXCLUDED FROM REPORTS</span>
          </div>
          <div style={{ fontFamily: th.display, fontSize: 44, letterSpacing: -1.6, lineHeight: 1, marginTop: 6 }}>
            {LEDGER.pending.length} <span style={{ fontStyle: 'italic', color: th.muted }}>items</span>
          </div>
          <div style={{ fontSize: 13, color: th.ink2, marginTop: 6 }}>
            Confirm them to flow into your reports. Or cancel to ignore.
          </div>
        </div>

        <div style={{ margin: '0 20px 14px', display: 'flex', gap: 8 }}>
          <div style={{
            flex: 1, height: 38, background: th.ink, color: th.paper, borderRadius: 19,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontSize: 12, fontWeight: 500, cursor: 'pointer'
          }}>
            <Icon name="check" size={14}/>Confirm all
          </div>
          <div style={{
            width: 38, height: 38, border: `1px solid ${th.line}`, borderRadius: 19,
            display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.muted, cursor: 'pointer'
          }}>
            <Icon name="x" size={14}/>
          </div>
        </div>

        <div style={{ padding: '0 20px' }}>
          {LEDGER.pending.map((p, i) => {
            const inc = p.amount > 0;
            const isFx = p.currency !== 'SGD';
            return (
              <div key={p.id} style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 16, marginBottom: 10 }}>
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                  <MerchantGlyph name={p.merchant} size={36} hue={(i * 60) % 360}/>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, alignItems: 'baseline' }}>
                      <div style={{ fontSize: 14, fontWeight: 500 }}>{p.merchant}</div>
                      <div style={{ fontFamily: th.body, fontSize: 15, fontWeight: 500, color: inc ? th.pos : th.ink, fontVariantNumeric: 'tabular-nums' }}>
                        {inc ? '+' : ''}{p.currency === 'JPY' ? '¥' : 'S$'}{Math.abs(p.amount).toLocaleString()}
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
                  <div style={{
                    flex: 1, height: 32, background: th.ink, color: th.paper, borderRadius: 16,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontSize: 12, fontWeight: 500, cursor: 'pointer'
                  }}>
                    <Icon name="check" size={12} stroke={2}/>Confirm
                  </div>
                  <div style={{
                    height: 32, padding: '0 14px', border: `1px solid ${th.line}`, borderRadius: 16,
                    display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: th.ink, cursor: 'pointer'
                  }}>
                    Edit
                  </div>
                  <div style={{
                    height: 32, width: 32, border: `1px solid ${th.line}`, borderRadius: 16,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.muted, cursor: 'pointer'
                  }}>
                    <Icon name="x" size={12}/>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
      <MobileTabBar active="pending" tabs={LEDGER_MOBILE_TABS}/>
    </div>
  );
}

export function ScreenTransferDetail() {
  const { theme: th } = useTweaks();
  const tg = LEDGER.transferGroups[1];

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <ScreenHeader title="Transfer" back={true} trailing={
            <div style={{
              width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer'
            }}><Icon name="dots" size={16}/></div>
          }/>

      <div style={{ padding: '0 24px 22px', textAlign: 'center' }}>
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

      <div style={{ padding: '0 20px' }}>
        <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 0, marginBottom: 12 }}>
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
    </div>
  );
}

export function ScreenCounterparties() {
  const { theme: th } = useTweaks();

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <ScreenHeader title="Merchants" trailing={
            <div style={{
              width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer'
            }}><Icon name="plus" size={16}/></div>
          }/>

        <div style={{ padding: '0 24px 18px' }}>
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

        <div style={{ margin: '0 20px 14px', height: 38, borderRadius: 19, background: th.paperAlt, display: 'flex', alignItems: 'center', gap: 10, padding: '0 14px', color: th.muted, fontSize: 13 }}>
          <Icon name="search" size={14}/>Search merchants & aliases…
        </div>

        <div style={{ padding: '0 20px' }}>
          {LEDGER.counterparties.map((c, i) => (
            <div key={c.id} style={{
              display: 'flex', alignItems: 'flex-start', gap: 12,
              padding: '14px 0', borderTop: i ? `0.5px solid ${th.line}` : 'none'
            }}>
              <MerchantGlyph name={c.name} size={40} hue={c.hue}/>
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
      <MobileTabBar active="pending" tabs={LEDGER_MOBILE_TABS}/>
    </div>
  );
}

export function ScreenRecurringTemplate() {
  const { theme: th } = useTweaks();
  const t = LEDGER.recurringTemplates[0];

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <ScreenHeader title="Recurring" back={true} trailing={
            <div style={{
              width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer'
            }}><Icon name="dots" size={16}/></div>
          }/>

        <div style={{ padding: '0 24px 22px' }}>
          <SchemaChip label="recurring_templates"/>
          <div style={{ fontFamily: th.display, fontSize: 36, letterSpacing: -0.8, lineHeight: 1.1, marginTop: 10 }}>
            <span style={{ fontStyle: 'italic', color: th.muted }}>Every 25th, you receive</span><br/>
            <span style={{ fontSize: 44 }}>S$5,800.00</span>
          </div>
          <div style={{ fontSize: 12, color: th.muted, marginTop: 8 }}>
            from <b style={{ color: th.ink2 }}>Acme</b> — next on May 25 · awaits your confirmation
          </div>
        </div>

        <div style={{ padding: '0 20px' }}>
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
        </div>

        <div style={{ padding: '24px 20px 8px' }}>
          <div style={{
            height: 50, borderRadius: 25, background: th.ink, color: th.paper,
            display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 500, cursor: 'pointer'
          }}>
            Save template
          </div>
        </div>
      </div>
    </div>
  );
}