'use client';

import { useTweaks } from './TweaksContext';
import { Icon } from './primitives';
import { fmtMoneyShort } from '@/lib/data';

interface CategoryRowProps {
  category: {
    id: string;
    name: string;
    icon: string;
    hue: number;
    spent: number;
    budget: number;
  };
}

export function CategoryRow({ category }: CategoryRowProps) {
  const { theme: th } = useTweaks();
  const cpct = (category.spent / category.budget) * 100;
  const over = cpct > 100;
  const remaining = category.budget - category.spent;

  return (
    <div style={{
      background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 14, marginBottom: 8,
      display: 'flex', alignItems: 'center', gap: 14, cursor: 'pointer'
    }}>
      <div style={{
        width: 38, height: 38, borderRadius: 19, background: `oklch(0.92 0.04 ${category.hue})`,
        display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, flexShrink: 0
      }}>
        <Icon name={category.icon} size={18}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <div style={{ fontSize: 14, fontWeight: 500 }}>{category.name}</div>
          <div style={{ fontFamily: th.mono, fontSize: 11, color: over ? th.neg : th.ink }}>
            {fmtMoneyShort(category.spent, th.currency)} / {fmtMoneyShort(category.budget, th.currency)}
          </div>
        </div>
        <div style={{ height: 3, background: th.paperAlt, borderRadius: 2, overflow: 'hidden', marginTop: 6, position: 'relative' }}>
          <div style={{ width: `${Math.min(cpct, 100)}%`, height: '100%', background: over ? th.neg : th.accent }}/>
        </div>
        <div style={{ fontSize: 11, color: over ? th.neg : th.muted, marginTop: 4 }}>
          {over ? `${fmtMoneyShort(-remaining, th.currency)} over` : `${fmtMoneyShort(remaining, th.currency)} left`}
        </div>
      </div>
    </div>
  );
}