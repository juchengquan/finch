'use client';

import { useTweaks } from '@/components/TweaksContext';
import { Icon, Card, Ring } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { MOCK, fmtMoneyShort } from '@/lib/data';
import { CategoryRow } from '@/components/CategoryRow';

export default function BudgetsPage() {
  const { theme: th } = useTweaks();
  const totalSpent = MOCK.categories.reduce((s, c) => s + c.spent, 0);
  const totalBudget = MOCK.categories.reduce((s, c) => s + c.budget, 0);
  const pct = Math.round((totalSpent / totalBudget) * 100);

  return (
    <MobilePage
      header={
        <ScreenHeader
          title="Budgets"
          trailing={<IconButton icon="search"/>}
        />
      }
    >
      <div style={{ padding: '0 20px 22px' }}>
        <PageHeader
          label="Spent of budget"
          value={<Ring value={totalSpent} max={totalBudget} size={120} stroke={10} color={th.accent} track={th.paperAlt}>
            <div style={{ textAlign: 'center' }}>
              <div style={{ fontFamily: th.display, fontSize: 28, letterSpacing: -0.6, lineHeight: 1 }}>{pct}%</div>
              <div style={{ fontSize: 9, color: th.muted, letterSpacing: 1, marginTop: 2 }}>USED</div>
            </div>
          </Ring>}
          sublabel={<>of <span style={{ fontFamily: th.mono }}>{fmtMoneyShort(totalBudget, th.currency)}</span></>}
          trend={{ text: 'On track for May', icon: 'check', color: th.pos }}
        />
      </div>

      <div style={{ padding: '0 20px 22px' }}>
        <Card>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
            <div style={{ fontFamily: th.display, fontSize: 18, fontStyle: 'italic' }}>Categories</div>
            <span style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.8 }}>SPENT / BUDGET</span>
          </div>
          {MOCK.categories.map((c) => (
            <CategoryRow key={c.id} category={c}/>
          ))}
        </Card>
      </div>
    </MobilePage>
  );
}