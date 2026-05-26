'use client';

import { useTweaks } from '@/components/TweaksContext';
import { fmtMoney } from '@/lib/data';

interface IconProps {
  name: string;
  size?: number;
  stroke?: number;
  style?: React.CSSProperties;
}

export function Icon({ name, size = 18, stroke = 1.5, style }: IconProps) {
  const props = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: stroke, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const, style };

  switch (name) {
    case 'fork':   return <svg {...props}><path d="M7 3v8a2 2 0 0 0 2 2h0a2 2 0 0 0 2-2V3M9 13v8M17 3c-2 0-3 2-3 5s1 5 3 5v8"/></svg>;
    case 'home':   return <svg {...props}><path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z"/></svg>;
    case 'car':    return <svg {...props}><path d="M3 13l2-6a2 2 0 0 1 2-1h10a2 2 0 0 1 2 1l2 6v6h-3v-2H6v2H3z"/><circle cx="7" cy="16" r="1.5"/><circle cx="17" cy="16" r="1.5"/></svg>;
    case 'bag':    return <svg {...props}><path d="M5 8h14l-1 12H6zM8 8V5a4 4 0 1 1 8 0v3"/></svg>;
    case 'film':   return <svg {...props}><rect x="3" y="4" width="18" height="16" rx="1"/><path d="M3 9h18M3 15h18M8 4v16M16 4v16"/></svg>;
    case 'heart':  return <svg {...props}><path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.5-7 10-7 10z"/></svg>;
    case 'sync':   return <svg {...props}><path d="M3 12a9 9 0 0 1 15-6.7L21 8M21 12a9 9 0 0 1-15 6.7L3 16M21 3v5h-5M3 21v-5h5"/></svg>;
    case 'dots':   return <svg {...props}><circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/></svg>;
    case 'plus':   return <svg {...props}><path d="M12 5v14M5 12h14"/></svg>;
    case 'search': return <svg {...props}><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>;
    case 'filter': return <svg {...props}><path d="M3 5h18M6 12h12M10 19h4"/></svg>;
    case 'chev':   return <svg {...props}><path d="m9 6 6 6-6 6"/></svg>;
    case 'chev-l': return <svg {...props}><path d="m15 6-6 6 6 6"/></svg>;
    case 'chev-d': return <svg {...props}><path d="m6 9 6 6 6-6"/></svg>;
    case 'chev-u': return <svg {...props}><path d="m6 15 6-6 6 6"/></svg>;
    case 'arrow-r':return <svg {...props}><path d="M5 12h14M13 5l7 7-7 7"/></svg>;
    case 'arrow-l':return <svg {...props}><path d="M19 12H5M11 5l-7 7 7 7"/></svg>;
    case 'clock':  return <svg {...props}><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>;
    case 'arrow-u':return <svg {...props}><path d="M12 19V5M5 12l7-7 7 7"/></svg>;
    case 'arrow-d':return <svg {...props}><path d="M12 5v14M5 12l7 7 7-7"/></svg>;
    case 'arrow-dl':return <svg {...props}><path d="M17 7L7 17M17 17H7V7"/></svg>;
    case 'arrow-ur':return <svg {...props}><path d="M7 17L17 7M7 7h10v10"/></svg>;
    case 'menu':   return <svg {...props}><path d="M4 6h16M4 12h16M4 18h16"/></svg>;
    case 'bell':   return <svg {...props}><path d="M6 8a6 6 0 0 1 12 0c0 6 3 7 3 7H3s3-1 3-7M10 21a2 2 0 0 0 4 0"/></svg>;
    case 'wallet': return <svg {...props}><rect x="3" y="6" width="18" height="14" rx="2"/><path d="M16 13h2M3 10h18"/></svg>;
    case 'chart':  return <svg {...props}><path d="M4 19V5M4 19h16M8 15v-4M12 15V9M16 15v-7"/></svg>;
    case 'cog':    return <svg {...props}><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2"/></svg>;
    case 'doc':    return <svg {...props}><path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9zM14 3v6h6M9 13h6M9 17h6"/></svg>;
    case 'target': return <svg {...props}><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/></svg>;
    case 'tag':    return <svg {...props}><path d="M3 3h8l10 10-8 8L3 11zM7 7h.01"/></svg>;
    case 'split':  return <svg {...props}><path d="M6 3v6a6 6 0 0 0 12 0V3M6 9v12M18 9v12"/></svg>;
    case 'edit':   return <svg {...props}><path d="M12 20h9M16.5 3.5a2 2 0 0 1 2.8 2.8L7 19l-4 1 1-4z"/></svg>;
    case 'check':  return <svg {...props}><path d="m5 12 5 5L20 7"/></svg>;
    case 'x':      return <svg {...props}><path d="M6 6l12 12M18 6L6 18"/></svg>;
    case 'calendar':return <svg {...props}><rect x="3" y="5" width="18" height="16" rx="1.5"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>;
    case 'mic':    return <svg {...props}><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>;
    case 'cam':    return <svg {...props}><path d="M3 7h4l2-3h6l2 3h4v13H3z"/><circle cx="12" cy="13" r="4"/></svg>;
    case 'sparkle':return <svg {...props}><path d="M12 3v18M3 12h18M5 5l14 14M5 19L19 5"/></svg>;
    default:       return <svg {...props}><circle cx="12" cy="12" r="8"/></svg>;
  }
}

interface MoneyProps {
  value: number;
  currency?: string;
  signed?: boolean;
  mono?: boolean;
  style?: React.CSSProperties;
}

export function Money({ value, currency = 'USD', signed = false, mono = true, style }: MoneyProps) {
  const s = fmtMoney(value, currency);
  return (
    <span style={{
      fontVariantNumeric: 'tabular-nums',
      fontFeatureSettings: '"tnum"',
      fontFamily: mono ? 'var(--font-mono)' : 'inherit',
      ...style,
    }}>
      {signed && value > 0 ? '+' : ''}{s}
    </span>
  );
}

interface SparklineProps {
  values: number[];
  width?: number;
  height?: number;
  color?: string;
  fillOpacity?: number;
  stroke?: number;
}

export function Sparkline({ values, width = 200, height = 50, color = 'var(--accent)', fillOpacity = 0.12, stroke = 1.5 }: SparklineProps) {
  const max = Math.max(...values, 1);
  const step = width / Math.max(values.length - 1, 1);
  const pts = values.map((v, i) => [i * step, height - (v / max) * (height - 4) - 2] as [number, number]);
  const d = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
  const fill = d + ` L${width} ${height} L0 ${height} Z`;

  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      <path d={fill} style={{ fill: color, opacity: fillOpacity }}/>
      <path d={d} fill="none" style={{ stroke: color }} strokeWidth={stroke} strokeLinejoin="round" strokeLinecap="round"/>
    </svg>
  );
}

interface BarChartProps {
  values: number[];
  labels?: string[];
  width?: number;
  height?: number;
  color?: string;
  highlight?: string;
  muted?: string;
}

export function BarChart({ values, labels, width = 280, height = 80, color = 'var(--ink)', highlight = 'var(--accent)', muted = 'var(--line)' }: BarChartProps) {
  const max = Math.max(...values, 1);
  const n = values.length;
  const gap = 4;
  const bw = (width - gap * (n - 1)) / n;

  return (
    <svg width={width} height={height + 14} viewBox={`0 0 ${width} ${height + 14}`}>
      {values.map((v, i) => {
        const h = (v / max) * height;
        const x = i * (bw + gap);
        const isLast = i === n - 1;
        return (
          <g key={i}>
            <rect x={x} y={height - h} width={bw} height={h} style={{ fill: isLast ? highlight : muted }} rx={1.5}/>
            {labels && <text x={x + bw / 2} y={height + 11} fontSize="9" style={{ fill: color }} opacity="0.55" textAnchor="middle" fontFamily="inherit">{labels[i]}</text>}
          </g>
        );
      })}
    </svg>
  );
}

interface DonutProps {
  slices: { value: number; color: string }[];
  size?: number;
  stroke?: number;
  gap?: number;
}

export function Donut({ slices, size = 140, stroke = 22, gap = 2 }: DonutProps) {
  const total = slices.reduce((s, x) => s + x.value, 0) || 1;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const arcs = slices.map((s, i) => {
    const len = (s.value / total) * c;
    const offset = -slices.slice(0, i).reduce((sum, p) => sum + (p.value / total) * c, 0);
    return { len, offset, color: s.color };
  });

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: 'rotate(-90deg)' }}>
      {arcs.map((a, i) => (
        <circle key={i} cx={size / 2} cy={size / 2} r={r} fill="none"
          style={{ stroke: a.color }} strokeWidth={stroke}
          strokeDasharray={`${Math.max(a.len - gap, 0.1)} ${c}`}
          strokeDashoffset={a.offset} />
      ))}
    </svg>
  );
}

interface StackedBarProps {
  slices: { value: number; color: string }[];
  width?: number;
  height?: number;
  radius?: number;
}

export function StackedBar({ slices, width = 280, height = 8, radius = 4 }: StackedBarProps) {
  const total = slices.reduce((s, x) => s + x.value, 0) || 1;
  const widths = slices.map((s, i) => Math.max((s.value / total) * width - (i < slices.length - 1 ? 2 : 0), 0));

  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      {widths.map((w, i) => {
        const x = widths.slice(0, i).reduce((sum, ww) => sum + ww + 2, 0);
        return <rect key={i} x={x} y={0} width={w} height={height} style={{ fill: slices[i].color }} rx={radius}/>;
      })}
    </svg>
  );
}

interface RingProps {
  value: number;
  max?: number;
  size?: number;
  stroke?: number;
  color?: string;
  track?: string;
  children?: React.ReactNode;
}

export function Ring({ value, max = 100, size = 48, stroke = 5, color = 'var(--accent)', track = 'var(--paper-alt)', children }: RingProps) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const pct = Math.max(0, Math.min(1, value / max));

  return (
    <div style={{ position: 'relative', width: size, height: size, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" style={{ stroke: track }} strokeWidth={stroke}/>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" style={{ stroke: color }} strokeWidth={stroke}
          strokeLinecap="round" strokeDasharray={`${pct * c} ${c}`}/>
      </svg>
      {children && <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{children}</div>}
    </div>
  );
}

interface MerchantGlyphProps {
  name: string;
  size?: number;
  hue?: number;
  bg?: string;
  fg?: string;
}

export function MerchantGlyph({ name, size = 36, hue, bg, fg = '#1a1614' }: MerchantGlyphProps) {
  const letter = (name || '?').trim().charAt(0).toUpperCase();
  const _hue = hue ?? (name ? name.charCodeAt(0) * 7 % 360 : 30);
  const _bg = bg || `oklch(0.92 0.04 ${_hue})`;

  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      background: _bg, color: fg,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: size * 0.42, fontWeight: 500, fontFamily: 'inherit',
      flexShrink: 0,
    }}>{letter}</div>
  );
}

export function CatDot({ hue, size = 8 }: { hue: number; size?: number }) {
  return <span style={{ display: 'inline-block', width: size, height: size, borderRadius: '50%', background: `oklch(0.65 0.13 ${hue})` }}/>;
}

interface CardProps {
  children: React.ReactNode;
  padding?: number;
  radius?: number;
  style?: React.CSSProperties;
}

export function Card({ children, padding = 14, radius = 14, style }: CardProps) {
  const { theme: th } = useTweaks();
  return (
    <div style={{
      background: th.card,
      border: `1px solid ${th.line}`,
      borderRadius: radius,
      padding,
      ...style,
    }}>
      {children}
    </div>
  );
}

interface ListItemRowProps {
  icon?: string;
  hue?: number;
  avatar?: { initials: string; color: string };
  leading?: React.ReactNode;
  trailing?: React.ReactNode;
  onClick?: () => void;
  children: React.ReactNode;
}

export function ListItemRow({ icon, hue, avatar, leading, trailing, onClick, children }: ListItemRowProps) {
  const { theme: th } = useTweaks();

  let leadingEl: React.ReactNode = null;
  if (icon !== undefined) {
    leadingEl = (
      <div style={{
        width: 38, height: 38, borderRadius: 19, background: `oklch(0.92 0.04 ${hue ?? 30})`,
        display: 'flex', alignItems: 'center', justifyContent: 'center', color: th.ink, flexShrink: 0
      }}>
        <Icon name={icon} size={18}/>
      </div>
    );
  } else if (avatar) {
    leadingEl = (
      <div style={{
        width: 38, height: 38, borderRadius: 8, background: avatar.color, color: '#fff',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontFamily: th.mono, fontSize: 10, fontWeight: 600, letterSpacing: 0.5, flexShrink: 0
      }}>{avatar.initials}</div>
    );
  } else if (leading) {
    leadingEl = leading;
  }

  return (
    <div
      onClick={onClick}
      style={{
        background: th.card, border: `1px solid ${th.line}`, borderRadius: 14,
        display: 'flex', alignItems: 'center', gap: 14, cursor: onClick ? 'pointer' : 'default',
        padding: 14, marginBottom: 8,
      }}
    >
      {leadingEl}
      <div style={{ flex: 1, minWidth: 0 }}>
        {children}
      </div>
      {trailing}
    </div>
  );
}

interface ProgressBarProps {
  value: number;
  max: number;
  color?: string;
  trackColor?: string;
  height?: number;
}

export function ProgressBar({ value, max, color, trackColor, height = 3 }: ProgressBarProps) {
  const { theme: th } = useTweaks();
  const pct = (value / max) * 100;
  const over = pct > 100;
  return (
    <div style={{ height, background: trackColor ?? th.paperAlt, borderRadius: 2, overflow: 'hidden' }}>
      <div style={{ width: `${Math.min(pct, 100)}%`, height: '100%', background: over ? th.neg : (color ?? th.accent) }}/>
    </div>
  );
}

