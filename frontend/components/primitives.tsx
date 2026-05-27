'use client';

import type { LucideIcon } from 'lucide-react';
import {
  Utensils, Home, Car, ShoppingBag, Film, Heart, RefreshCw, MoreHorizontal, Plus, Search,
  SlidersHorizontal, ChevronRight, ChevronLeft, ChevronDown, ChevronUp, ArrowRight, ArrowLeft,
  ArrowUp, ArrowDown, ArrowDownLeft, ArrowUpRight, Menu, Bell, Wallet, ChartColumn, Settings,
  FileText, Target, Tag, Split, Pencil, Check, X, Calendar, Mic, Camera, Sparkles, Clock, Circle,
  Download, Upload, ArrowRightLeft, Coins,
} from 'lucide-react';

import { useMoney } from '@/components/use-money';
import { cn } from '@/lib/utils';

const ICONS: Record<string, LucideIcon> = {
  fork: Utensils, home: Home, car: Car, bag: ShoppingBag, film: Film, heart: Heart,
  sync: RefreshCw, dots: MoreHorizontal, plus: Plus, search: Search, filter: SlidersHorizontal,
  chev: ChevronRight, 'chev-l': ChevronLeft, 'chev-d': ChevronDown, 'chev-u': ChevronUp,
  'arrow-r': ArrowRight, 'arrow-l': ArrowLeft, 'arrow-u': ArrowUp, 'arrow-d': ArrowDown,
  'arrow-dl': ArrowDownLeft, 'arrow-ur': ArrowUpRight, menu: Menu, bell: Bell, wallet: Wallet,
  chart: ChartColumn, cog: Settings, doc: FileText, target: Target, tag: Tag, split: Split,
  edit: Pencil, check: Check, x: X, calendar: Calendar, mic: Mic, cam: Camera, sparkle: Sparkles,
  clock: Clock, download: Download, upload: Upload, swap: ArrowRightLeft, coins: Coins,
};

interface IconProps {
  name: string;
  size?: number;
  stroke?: number;
  className?: string;
  style?: React.CSSProperties;
}

export function Icon({ name, size = 18, stroke = 1.5, className, style }: IconProps) {
  const Cmp = ICONS[name] ?? Circle;
  return <Cmp size={size} strokeWidth={stroke} className={className} style={style} aria-hidden />;
}

interface MoneyProps {
  value: number;
  signed?: boolean;
  mono?: boolean;
  className?: string;
  style?: React.CSSProperties;
}

export function Money({ value, signed = false, mono = true, className, style }: MoneyProps) {
  const { fmt } = useMoney();
  return (
    <span className={cn('tabular-nums', mono && 'font-mono', className)} style={style}>
      {fmt(value, { signed })}
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

export function Sparkline({ values, width = 200, height = 50, color = 'var(--primary)', fillOpacity = 0.12, stroke = 1.5 }: SparklineProps) {
  if (values.length === 0) return <svg aria-hidden width={width} height={height} />;
  // Normalise to the value range so series with negative or large-offset values
  // (e.g. credit-card balances) still fill the band.
  const min = Math.min(...values);
  const range = Math.max(...values) - min || 1;
  const step = width / Math.max(values.length - 1, 1);
  const pts = values.map((v, i) => [i * step, height - ((v - min) / range) * (height - 4) - 2] as [number, number]);
  const d = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
  const fill = d + ` L${width} ${height} L0 ${height} Z`;

  return (
    <svg aria-hidden width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      <path d={fill} style={{ fill: color, opacity: fillOpacity }} />
      <path d={d} fill="none" style={{ stroke: color }} strokeWidth={stroke} strokeLinejoin="round" strokeLinecap="round" />
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
  className?: string;
}

export function BarChart({ values, labels, width = 280, height = 80, color = 'var(--foreground)', highlight = 'var(--primary)', muted = 'var(--border)', className }: BarChartProps) {
  const max = Math.max(...values, 1);
  const n = values.length;
  const gap = 4;
  const bw = (width - gap * (n - 1)) / n;

  return (
    <svg aria-hidden width={width} height={height + 14} viewBox={`0 0 ${width} ${height + 14}`} className={className} preserveAspectRatio="none">
      {values.map((v, i) => {
        const h = (v / max) * height;
        const x = i * (bw + gap);
        const isLast = i === n - 1;
        return (
          <g key={i}>
            <rect x={x} y={height - h} width={bw} height={h} style={{ fill: isLast ? highlight : muted }} rx={1.5} />
            {labels && <text x={x + bw / 2} y={height + 11} fontSize="9" style={{ fill: color }} opacity="0.55" textAnchor="middle" fontFamily="inherit">{labels[i]}</text>}
          </g>
        );
      })}
    </svg>
  );
}

interface AreaChartProps {
  series: { values: number[]; color: string; fillOpacity?: number }[];
  labels?: string[];
  width?: number;
  height?: number;
  className?: string;
}

export function AreaChart({ series, labels, width = 310, height = 120, className }: AreaChartProps) {
  const max = Math.max(...series.flatMap((s) => s.values), 1);
  const n = Math.max(...series.map((s) => s.values.length), 1);
  const step = width / Math.max(n - 1, 1);
  const h = labels ? height - 14 : height;
  const path = (vals: number[]) =>
    vals
      .map((v, i) => `${i ? 'L' : 'M'}${(i * step).toFixed(1)} ${(h - (v / max) * (h - 4) - 2).toFixed(1)}`)
      .join(' ');

  return (
    <svg aria-hidden width={width} height={height} viewBox={`0 0 ${width} ${height}`} className={className} preserveAspectRatio="none">
      {series.map((s, si) => {
        const d = path(s.values);
        return (
          <g key={si}>
            <path d={`${d} L${width} ${h} L0 ${h} Z`} style={{ fill: s.color, opacity: s.fillOpacity ?? 0.12 }} />
            <path d={d} fill="none" style={{ stroke: s.color }} strokeWidth={1.5} strokeLinejoin="round" strokeLinecap="round" />
          </g>
        );
      })}
      {labels?.map((l, i) => (
        <text key={i} x={i * step} y={height - 2} fontSize="9" style={{ fill: 'var(--muted-foreground)' }} textAnchor={i === 0 ? 'start' : i === labels.length - 1 ? 'end' : 'middle'}>
          {l}
        </text>
      ))}
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
    <svg aria-hidden width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: 'rotate(-90deg)' }}>
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
    <svg aria-hidden width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      {widths.map((w, i) => {
        const x = widths.slice(0, i).reduce((sum, ww) => sum + ww + 2, 0);
        return <rect key={i} x={x} y={0} width={w} height={height} style={{ fill: slices[i].color }} rx={radius} />;
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

export function Ring({ value, max = 100, size = 48, stroke = 5, color = 'var(--primary)', track = 'var(--secondary)', children }: RingProps) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const pct = Math.max(0, Math.min(1, value / max));

  return (
    <div className="relative inline-flex items-center justify-center" style={{ width: size, height: size }}>
      <svg aria-hidden width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" style={{ stroke: track }} strokeWidth={stroke} />
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" style={{ stroke: color }} strokeWidth={stroke}
          strokeLinecap="round" strokeDasharray={`${pct * c} ${c}`} />
      </svg>
      {children && <div className="absolute inset-0 flex items-center justify-center">{children}</div>}
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

export function MerchantGlyph({ name, size = 36, hue, bg, fg = 'var(--foreground)' }: MerchantGlyphProps) {
  const letter = (name || '?').trim().charAt(0).toUpperCase();
  const _hue = hue ?? (name ? (name.charCodeAt(0) * 7) % 360 : 30);
  const _bg = bg || `oklch(0.9 0.05 ${_hue})`;

  return (
    <div
      className="flex shrink-0 items-center justify-center rounded-full font-medium"
      style={{ width: size, height: size, background: _bg, color: fg, fontSize: size * 0.42 }}
    >
      {letter}
    </div>
  );
}

export function CatDot({ hue, size = 8 }: { hue: number; size?: number }) {
  return <span className="inline-block rounded-full" style={{ width: size, height: size, background: `oklch(0.65 0.13 ${hue})` }} />;
}

// Vertical category-colored accent bar, used as the leading element of transaction rows.
export function CatBar({ hue, className }: { hue: number; className?: string }) {
  return (
    <span
      aria-hidden
      className={cn('w-1 shrink-0 self-stretch rounded-full', className)}
      style={{ background: `oklch(0.65 0.13 ${hue})` }}
    />
  );
}
