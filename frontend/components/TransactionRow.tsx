'use client';

import Link from 'next/link';
import { useTweaks } from './TweaksContext';
import { Icon, Sparkline } from './primitives';
import { fmtMoneyShort } from '@/lib/data';

interface TransactionRowProps {
  account: {
    id: string;
    name: string;
    last4: string;
    color: string;
    balance: number;
  };
  sparklineValues?: number[];
  href?: string;
}

export function TransactionRow({ account, sparklineValues = [20,30,18,42,52,38,45,60,48,55,72,68,75], href }: TransactionRowProps) {
  const { theme: th } = useTweaks();

  const content = (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12, padding: '14px',
      borderTop: `0.5px solid ${th.line}`, cursor: 'pointer'
    }}>
      <div style={{
        width: 38, height: 38, borderRadius: 8, background: account.color, color: '#fff',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontFamily: th.mono, fontSize: 10, fontWeight: 600, letterSpacing: 0.5, flexShrink: 0
      }}>{account.last4.slice(-2)}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 500, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{account.name}</div>
        <div style={{ fontFamily: th.mono, fontSize: 10, color: th.muted, letterSpacing: 0.5, marginTop: 2 }}>•••• {account.last4}</div>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <Sparkline values={sparklineValues} width={56} height={20} color={account.balance < 0 ? th.neg : th.accent} stroke={1.2} fillOpacity={0.08}/>
        <div style={{ textAlign: 'right', minWidth: 78 }}>
          <div style={{
            fontFamily: th.body, fontSize: 16, fontWeight: 500, lineHeight: 1,
            color: account.balance < 0 ? th.neg : th.ink, fontVariantNumeric: 'tabular-nums'
          }}>
            {account.balance < 0 ? '−' : ''}{fmtMoneyShort(Math.abs(account.balance), th.currency)}
          </div>
        </div>
        <Icon name="chev" size={12} style={{ color: th.muted, flexShrink: 0 }}/>
      </div>
    </div>
  );

  if (href) {
    return (
      <Link href={href} style={{ display: 'block', textDecoration: 'none', color: 'inherit' }}>
        {content}
      </Link>
    );
  }

  return content;
}