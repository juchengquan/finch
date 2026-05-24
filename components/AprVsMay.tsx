'use client';

import { useTweaks } from './TweaksContext';
import { fmtMoneyShort } from '@/lib/data';

interface AprVsMayProps {
  data: {
    name: string;
    a: number;
    b: number;
    d: number;
  }[];
}

export function AprVsMay({ data }: AprVsMayProps) {
  const { theme: th } = useTweaks();

  return (
    <div>
      {data.map((c) => (
        <div key={c.name} style={{ display: 'flex', alignItems: 'center', padding: '12px 0', borderTop: `1px solid ${th.line}` }}>
          <div style={{ flex: 1, fontSize: 14 }}>{c.name}</div>
          <div style={{ fontFamily: th.mono, fontSize: 11, color: th.muted, marginRight: 14 }}>
            {fmtMoneyShort(c.a, th.currency)} → {fmtMoneyShort(c.b, th.currency)}
          </div>
          <div style={{ fontFamily: th.mono, fontSize: 12, fontWeight: 600, color: c.d < 0 ? th.pos : th.neg }}>
            {c.d > 0 ? '+' : ''}{c.d}%
          </div>
        </div>
      ))}
    </div>
  );
}