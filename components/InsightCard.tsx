'use client';

import { useTweaks } from './TweaksContext';
import { Icon } from './primitives';

interface InsightCardProps {
  insight: {
    tone: 'pos' | 'warn' | 'neut';
    icon: string;
    title: string;
    body: string;
  };
}

export function InsightCard({ insight }: InsightCardProps) {
  const { theme: th } = useTweaks();
  const c = insight.tone === 'pos' ? th.pos : insight.tone === 'warn' ? th.warn : th.accent;

  return (
    <div style={{
      background: th.card, border: `1px solid ${th.line}`, borderRadius: 14, padding: 16, marginBottom: 10,
      display: 'flex', gap: 12
    }}>
      <div style={{
        width: 32, height: 32, borderRadius: 16, background: `${c}1a`, color: c,
        display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0
      }}>
        <Icon name={insight.icon} size={16}/>
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontFamily: th.display, fontSize: 18, letterSpacing: -0.2, marginBottom: 4 }}>{insight.title}</div>
        <div style={{ fontSize: 12, color: th.ink2, lineHeight: 1.45 }}>{insight.body}</div>
      </div>
    </div>
  );
}