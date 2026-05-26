'use client';

import { useTweaks } from './TweaksContext';
import { Money } from './primitives';

interface ScheduledItemProps {
  item: {
    day: number;
    month: string;
    label: string;
    amount: number;
    type: string;
    color: string;
  };
}

export function ScheduledItem({ item }: ScheduledItemProps) {
  const { theme: th } = useTweaks();

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: 14, background: th.card, border: `1px solid ${th.line}`, borderRadius: 14 }}>
      <div style={{ width: 44, textAlign: 'center', flexShrink: 0 }}>
        <div style={{ fontFamily: th.mono, fontSize: 9, letterSpacing: 1, color: th.muted, textTransform: 'uppercase' }}>{item.month}</div>
        <div style={{ fontFamily: th.display, fontSize: 22, letterSpacing: -0.4, lineHeight: 1, marginTop: 1 }}>{item.day}</div>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 500 }}>{item.label}</div>
        <div style={{ fontSize: 11, color: th.muted, marginTop: 2, display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: item.color }}/>
          {item.type}
        </div>
      </div>
      <Money value={item.amount} currency={th.currency} style={{ fontSize: 14, fontWeight: 500, color: item.amount > 0 ? th.pos : th.ink }}/>
    </div>
  );
}