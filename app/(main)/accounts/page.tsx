'use client';

import Link from 'next/link';
import { useTweaks } from '@/components/TweaksContext';
import { Icon, Money, Card } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK, fmtMoneyShort } from '@/lib/data';

const DEFAULT_OPEN_GROUPS = new Set(['cash', 'credit', 'invest']);

export default function AccountsPage() {
  const { theme: th } = useTweaks();
  const total = MOCK.accounts.reduce((s, a) => s + a.balance, 0);

  const groupedAccounts = MOCK.accountGroups.map((g) => ({ ...g, accounts: MOCK.accounts.filter((a) => a.group === g.id) }));

  return (
    <MobilePage>
      <ScreenHeader
        title="Accounts"
        trailing={<IconButton icon="search" aria-label="Search"/>}
      />

      <div style={{ padding: '0 20px 22px' }}>
        <PageHeader
          label="Net worth · all accounts"
          value={<Money value={total} currency={th.currency} mono={false} style={{ fontFamily: th.display }}/>}
          sublabel={<span style={{ color: th.pos }}>+ <Money value={812} currency={th.currency}/> this month</span>}
        />
      </div>

      <div style={{ padding: '0 20px 120px' }}>
        {groupedAccounts.map((g) => {
          const groupTotal = g.accounts.reduce((s: number, a: typeof MOCK.accounts[0]) => s + a.balance, 0);
          const empty = g.accounts.length === 0;
          const isOpen = DEFAULT_OPEN_GROUPS.has(g.id);

          return (
            <div key={g.id} style={{ marginBottom: 14 }}>
              <details open={isOpen} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                <summary style={{ display: 'flex', alignItems: 'center', gap: 10, paddingBottom: 8, cursor: 'pointer', listStyle: 'none' }}>
                  <Icon name={isOpen ? 'chev-d' : 'chev'} size={12} style={{ color: th.muted }}/>
                  <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic', letterSpacing: -0.2, flex: 1 }}>{g.name}</div>
                  <span style={{ fontFamily: th.mono, fontSize: 11, color: empty ? th.muted : th.ink2, letterSpacing: 0.3 }}>
                    {empty ? '—' : `${g.accounts.length} · ${groupTotal < 0 ? '−' : ''}${fmtMoneyShort(groupTotal, th.currency)}`}
                  </span>
                </summary>
                {empty ? (
                  <button type="button" style={{ height: 52, borderRadius: 12, border: `1px dashed ${th.line}`, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: th.muted, fontSize: 12, cursor: 'pointer', background: 'none', fontFamily: 'inherit' }}>
                    <Icon name="plus" size={14}/>Add account
                  </button>
                ) : (
                  <Card padding={0}>
                    {g.accounts.map((a, i) => (
                      <Link key={a.id} href={`/accounts/${a.id}`} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px', borderTop: i ? `0.5px solid ${th.line}` : 'none', cursor: 'pointer', textDecoration: 'none', color: 'inherit' }}>
                        <div style={{ width: 38, height: 38, borderRadius: 8, background: a.color, color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: th.mono, fontSize: 10, fontWeight: 600, letterSpacing: 0.5, flexShrink: 0 }}>{a.last4.slice(-2)}</div>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontSize: 14, fontWeight: 500 }}>{a.name}</div>
                          <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.5, marginTop: 2 }}>•••• {a.last4}</div>
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                          <div style={{ textAlign: 'right', minWidth: 70 }}>
                            <div style={{ fontFamily: th.body, fontSize: 16, fontWeight: 500, lineHeight: 1, color: a.balance < 0 ? th.neg : th.ink, fontVariantNumeric: 'tabular-nums' }}>
                              {a.balance < 0 ? '−' : ''}{fmtMoneyShort(Math.abs(a.balance), th.currency)}
                            </div>
                          </div>
                          <Icon name="chev" size={12} style={{ color: th.muted, flexShrink: 0 }}/>
                        </div>
                      </Link>
                    ))}
                  </Card>
                )}
              </details>
            </div>
          );
        })}
      </div>
    </MobilePage>
  );
}