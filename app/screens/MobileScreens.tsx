'use client';

import { useState } from 'react';
import { useTweaks } from '@/components/TweaksContext';
import { Icon, Money, Sparkline, BarChart, MerchantGlyph, Ring } from '@/components/primitives';
import { ScreenHeader, MobileTabBar } from '@/components/MobileComponents';
import { MOCK, fmtMoney, fmtMoneyShort, catById, acctById } from '@/lib/data';
import { InsightCard } from '@/components/InsightCard';
import { AprVsMay } from '@/components/AprVsMay';
import { CategoryRow } from '@/components/CategoryRow';

const MAIN_MOBILE_TABS = [
  { id: 'accounts',  icon: 'wallet',   label: 'Accounts' },
  { id: 'budgets',   icon: 'target',   label: 'Budgets' },
  { id: 'add',       icon: 'plus',     label: 'Add',      pinned: true },
  { id: 'scheduled', icon: 'calendar', label: 'Scheduled' },
  { id: 'insights',  icon: 'chart',   label: 'Insights' },
];

export function ScreenAccounts() {
  const { theme: th } = useTweaks();
  const total = MOCK.accounts.reduce((s, a) => s + a.balance, 0);
  const [openGroups, setOpenGroups] = useState({ cash: true, credit: true, invest: true, loan: false });

  const groupedAccounts = MOCK.accountGroups
    .map((g) => ({ ...g, accounts: MOCK.accounts.filter((a) => a.group === g.id) }));

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <ScreenHeader title="Accounts" trailing={
            <div style={{
              width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer'
            }}><Icon name="plus" size={16}/></div>
          }/>

        <div style={{ padding: '0 24px 22px' }}>
          <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>Net worth · all accounts</div>
          <div style={{
            fontFamily: th.display, fontSize: 52, letterSpacing: -2, lineHeight: 1, marginTop: 6, fontWeight: 400,
          }}>
            <Money value={total} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
          </div>
          <div style={{ fontSize: 12, color: th.pos, marginTop: 6 }}>+ <Money value={812} currency={th.currency}/> this month</div>
        </div>

        <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
          {groupedAccounts.map((g) => {
            const groupTotal = g.accounts.reduce((s: number, a: typeof MOCK.accounts[0]) => s + a.balance, 0);
            const empty = g.accounts.length === 0;
            return (
              <div key={g.id}>
                <div style={{
                  display: 'flex', alignItems: 'center', gap: 10, padding: '0 4px 8px', cursor: 'pointer'
                }}>
                  <Icon name="chev-d" size={12} style={{ color: th.muted }}/>
                  <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic', letterSpacing: -0.2, flex: 1 }}>{g.name}</div>
                  <span style={{ fontFamily: th.mono, fontSize: 11, color: empty ? th.muted : th.ink2, letterSpacing: 0.3 }}>
                    {empty ? '—' : `${g.accounts.length} · ${groupTotal < 0 ? '−' : ''}${fmtMoneyShort(groupTotal, th.currency)}`}
                  </span>
                </div>
                {empty ? (
                  <div style={{
                    height: 52, borderRadius: 12, border: `1px dashed ${th.line}`,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: th.muted, fontSize: 12, cursor: 'pointer'
                  }}>
                    <Icon name="plus" size={14}/>Add a {g.name.toLowerCase()} account
                  </div>
                ) : (
                  <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, overflow: 'hidden' }}>
                    {g.accounts.map((a, i) => (
                      <div key={a.id} style={{
                        display: 'flex', alignItems: 'center', gap: 12, padding: '14px 14px',
                        borderTop: i ? `0.5px solid ${th.line}` : 'none', cursor: 'pointer'
                      }}>
                        <div style={{
                          width: 38, height: 38, borderRadius: 8, background: a.color, color: '#fff',
                          display: 'flex', alignItems: 'center', justifyContent: 'center',
                          fontFamily: th.mono, fontSize: 10, fontWeight: 600, letterSpacing: 0.5, flexShrink: 0
                        }}>{a.last4.slice(-2)}</div>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontSize: 14, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{a.name}</div>
                          <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.5, marginTop: 2 }}>•••• {a.last4}</div>
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                          <Sparkline values={[20,30,18,42,52,38,45,60,48,55,72,68,75]} width={56} height={20} color={a.balance < 0 ? th.neg : th.accent} stroke={1.2} fillOpacity={0.08}/>
                          <div style={{ textAlign: 'right', minWidth: 78 }}>
                            <div style={{
                              fontFamily: th.body, fontSize: 16, fontWeight: 500, lineHeight: 1,
                              color: a.balance < 0 ? th.neg : th.ink, fontVariantNumeric: 'tabular-nums'
                            }}>
                              {a.balance < 0 ? '−' : ''}{fmtMoneyShort(Math.abs(a.balance), th.currency)}
                            </div>
                          </div>
                          <Icon name="chev" size={12} style={{ color: th.muted, flexShrink: 0 }}/>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
          <div style={{
            marginTop: 4, height: 52, borderRadius: 12, border: `1px dashed ${th.line}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: th.muted, fontSize: 13, cursor: 'pointer'
          }}>
            <Icon name="plus" size={16}/>Link a new account
          </div>
        </div>
      </div>
      <MobileTabBar active="accounts" tabs={MAIN_MOBILE_TABS}/>
    </div>
  );
}

export function ScreenBudgets() {
  const { theme: th } = useTweaks();
  const totalSpent = MOCK.categories.reduce((s, c) => s + c.spent, 0);
  const totalBudget = MOCK.categories.reduce((s, c) => s + c.budget, 0);
  const pct = (totalSpent / totalBudget) * 100;

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <ScreenHeader title="Budgets" back={false} trailing={
            <div style={{
              width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer'
            }}><Icon name="edit" size={14}/></div>
          }/>

        <div style={{ padding: '0 24px 22px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 22 }}>
            <Ring value={totalSpent} max={totalBudget} size={120} stroke={10} color={th.accent} track={th.paperAlt}>
              <div style={{ textAlign: 'center' }}>
                <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.6, lineHeight: 1 }}>{Math.round(pct)}%</div>
                <div style={{ fontSize: 9, color: th.muted, letterSpacing: 1, marginTop: 2 }}>USED</div>
              </div>
            </Ring>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 11, color: th.muted, letterSpacing: 1, textTransform: 'uppercase' }}>Spent of budget</div>
              <div style={{ fontFamily: th.display, fontSize: 30, letterSpacing: -0.6, marginTop: 2 }}>
                <Money value={totalSpent} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>
              </div>
              <div style={{ fontSize: 12, color: th.muted, marginTop: 2 }}>of <Money value={totalBudget} currency={th.currency}/></div>
              <div style={{
                marginTop: 8, padding: '4px 10px', display: 'inline-flex', alignItems: 'center', gap: 6,
                background: `${th.pos}1a`, color: th.pos, borderRadius: 10, fontSize: 11, fontWeight: 500
              }}>
                <Icon name="check" size={12}/>On track for May
              </div>
            </div>
          </div>
        </div>

        <div style={{ padding: '0 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8, padding: '0 4px' }}>
            <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic' }}>Categories</div>
            <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>SPENT / BUDGET</span>
          </div>
          {MOCK.categories.map((c) => (
            <CategoryRow key={c.id} category={c}/>
          ))}
        </div>
      </div>
      <MobileTabBar active="budgets" tabs={MAIN_MOBILE_TABS}/>
    </div>
  );
}

export function ScreenInsights() {
  const { theme: th } = useTweaks();

  return (
    <div style={{ height: '100%', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative' }}>
      <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 110 }}>
        <ScreenHeader title="Insights" back={false} trailing={
            <div style={{
              width: 36, height: 36, borderRadius: 18, border: `1px solid ${th.line}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, cursor: 'pointer'
            }}><Icon name="calendar" size={16}/></div>
          }/>

        <div style={{ padding: '0 20px' }}>
          <div style={{ borderTop: `1px solid ${th.line}`, paddingTop: 18, marginBottom: 22 }}>
            <div style={{ fontSize: 10, color: th.muted, letterSpacing: 1.2, textTransform: 'uppercase' }}>You're spending less</div>
            <div style={{ fontFamily: th.display, fontSize: 60, letterSpacing: -2, lineHeight: 1, marginTop: 6 }}>↓ 8.4%</div>
            <div style={{ fontFamily: th.display, fontStyle: 'italic', fontSize: 16, color: th.ink2, marginTop: 6 }}>
              than April. Mostly less <span style={{ color: th.accent }}>Shopping</span>.
            </div>
          </div>

          <div style={{ background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 18, marginBottom: 16 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
              <div style={{ fontSize: 13, fontWeight: 600 }}>Monthly spending</div>
              <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>LAST 12 MO</div>
            </div>
            <BarChart values={MOCK.monthly.map(m => m.v)} labels={MOCK.monthly.map(m => m.m[0])} width={310} height={120} color={th.muted} highlight={th.accent} muted={th.paperAlt}/>
          </div>

          {MOCK.insights.map((ins) => (
            <InsightCard key={ins.title} insight={ins}/>
          ))}

          <div style={{ marginTop: 22 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
              <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic' }}>Apr vs May</div>
              <span style={{ fontSize: 11, color: th.muted }}>Top changes</span>
            </div>
            <AprVsMay data={MOCK.aprVsMay}/>
          </div>
        </div>
      </div>
      <MobileTabBar active="insights" tabs={MAIN_MOBILE_TABS}/>
    </div>
  );
}