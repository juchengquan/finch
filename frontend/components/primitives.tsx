'use client';

import type { LucideIcon } from 'lucide-react';
import {
  Utensils, Home, Car, ShoppingBag, Film, Heart, RefreshCw, MoreHorizontal, Plus, Search,
  SlidersHorizontal, ChevronRight, ChevronLeft, ChevronDown, ChevronUp, ArrowRight, ArrowLeft,
  ArrowUp, ArrowDown, ArrowDownLeft, ArrowUpRight, Menu, Bell, Wallet, ChartColumn, Settings,
  FileText, Target, Tag, Tags, Split, Pencil, Check, X, Calendar, Mic, Camera, Sparkles, Clock, Circle,
  Download, Upload, ArrowRightLeft, Coins, Trash2, Bookmark, Paperclip, Image as ImageIcon,
  Banknote, ShieldCheck,
} from 'lucide-react';

import { useMoney } from '@/components/use-money';
import { cn } from '@/lib/utils';

const ICONS: Record<string, LucideIcon> = {
  fork: Utensils, home: Home, car: Car, bag: ShoppingBag, film: Film, heart: Heart,
  sync: RefreshCw, dots: MoreHorizontal, plus: Plus, search: Search, filter: SlidersHorizontal,
  chev: ChevronRight, 'chev-l': ChevronLeft, 'chev-d': ChevronDown, 'chev-u': ChevronUp,
  'arrow-r': ArrowRight, 'arrow-l': ArrowLeft, 'arrow-u': ArrowUp, 'arrow-d': ArrowDown,
  'arrow-dl': ArrowDownLeft, 'arrow-ur': ArrowUpRight, menu: Menu, bell: Bell, wallet: Wallet,
  chart: ChartColumn, cog: Settings, doc: FileText, target: Target, tag: Tag, tags: Tags, split: Split,
  edit: Pencil, pencil: Pencil, check: Check, x: X, calendar: Calendar, mic: Mic, cam: Camera, sparkle: Sparkles,
  clock: Clock, download: Download, upload: Upload, swap: ArrowRightLeft, coins: Coins, trash: Trash2,
  bookmark: Bookmark, paperclip: Paperclip, image: ImageIcon, banknote: Banknote,
  'shield-check': ShieldCheck,
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
  /** Background colour. Hex (`#xxxxxx`), CSS colour string, or omitted for a
   *  deterministic per-name fallback. */
  color?: string | null;
  fg?: string;
}

export function MerchantGlyph({ name, size = 36, color, fg = 'var(--foreground)' }: MerchantGlyphProps) {
  const letter = (name || '?').trim().charAt(0).toUpperCase();
  const fallbackHue = name ? (name.charCodeAt(0) * 7) % 360 : 30;
  const bg = color || `oklch(0.9 0.05 ${fallbackHue})`;

  return (
    <div
      className="flex shrink-0 items-center justify-center rounded-full font-medium"
      style={{ width: size, height: size, background: bg, color: fg, fontSize: size * 0.42 }}
    >
      {letter}
    </div>
  );
}

const FALLBACK_CAT_COLOR = '#9ca3af';

export function CatDot({ color, size = 8 }: { color: string | null | undefined; size?: number }) {
  return <span className="inline-block rounded-full" style={{ width: size, height: size, background: color || FALLBACK_CAT_COLOR }} />;
}

// Vertical category-colored accent bar, used as the leading element of transaction rows.
export function CatBar({ color, className }: { color: string | null | undefined; className?: string }) {
  return (
    <span
      aria-hidden
      className={cn('w-1 shrink-0 self-stretch rounded-full', className)}
      style={{ background: color || FALLBACK_CAT_COLOR }}
    />
  );
}

interface CalendarHeatmapProps {
  /** Day buckets, oldest-first; each entry is one calendar day. */
  values: { date: string; value: number }[];
  cellSize?: number;
  gap?: number;
  emptyColor?: string;
  color?: string;
  className?: string;
}

interface SankeyNode {
  name: string;
  value: number;
  color?: string;
}

interface SankeyProps {
  /** Source nodes (e.g. income sources). */
  left: SankeyNode[];
  /** Target nodes (e.g. expense categories + a "Remaining" stub for leftovers). */
  right: SankeyNode[];
  width?: number;
  height?: number;
  /** Width of the left + right "node" rectangles. */
  nodeWidth?: number;
  /** Vertical padding between nodes within each column. */
  nodeGap?: number;
  className?: string;
}

/**
 * Single-source-to-many-targets Sankey. The left column is one stack of source
 * nodes; flows fan out to the right column proportionally to the targets'
 * values. When `left` has multiple nodes, flows are distributed pro-rata across
 * sources (each left source contributes the same share to every right target).
 *
 * Designed for income → categories visualisations: `left` is income sources
 * (or a single "Income" node) and `right` is expense categories, with the
 * caller appending a stub like { name: "Saved", value: leftover } so widths
 * sum across the canvas.
 */
export function Sankey({
  left,
  right,
  width = 480,
  height = 200,
  nodeWidth = 8,
  nodeGap = 4,
  className,
}: SankeyProps) {
  const leftTotal = left.reduce((s, n) => s + n.value, 0);
  const rightTotal = right.reduce((s, n) => s + n.value, 0);
  if (leftTotal <= 0 || rightTotal <= 0) {
    return <svg aria-hidden width={width} height={height} className={className} />;
  }
  const total = Math.max(leftTotal, rightTotal);
  // Each pixel of vertical space represents `total / usableH` units of value.
  const leftGaps = nodeGap * (left.length - 1);
  const rightGaps = nodeGap * (right.length - 1);
  const usableH = height - Math.max(leftGaps, rightGaps);

  // Position each node's top + bottom edges. Each top is the cumulative sum of
  // preceding heights + gaps.
  const positionsFor = (nodes: SankeyNode[]) => {
    const heights = nodes.map((n) => (n.value / total) * usableH);
    return nodes.map((node, i) => {
      const top = heights.slice(0, i).reduce((s, h) => s + h + nodeGap, 0);
      return { top, bottom: top + heights[i], height: heights[i], node };
    });
  };
  const leftPositions = positionsFor(left);
  const rightPositions = positionsFor(right);

  const leftEdge = nodeWidth;
  const rightEdge = width - nodeWidth;
  const midA = leftEdge + (width - 2 * nodeWidth) * 0.4;
  const midB = leftEdge + (width - 2 * nodeWidth) * 0.6;

  // Pro-rata distribution: flow_ij = (leftI / leftTotal) × rightJ-height.
  // From the left side, each source bar is divided vertically by the right
  // nodes' shares; from the right side, each target bar is divided by the
  // left nodes' shares. Walking both cursors in the same (j, i) order keeps
  // the ribbon corners aligned.
  const ribbons: { lTop: number; lBot: number; rTop: number; rBot: number; color: string }[] = [];
  const leftCursors = leftPositions.map((lp) => lp.top);
  for (let j = 0; j < rightPositions.length; j++) {
    const rp = rightPositions[j];
    let rCursor = rp.top;
    for (let i = 0; i < leftPositions.length; i++) {
      const lp = leftPositions[i];
      const flowH = lp.height * (rp.node.value / rightTotal);
      const lTop = leftCursors[i];
      const lBot = lTop + flowH;
      const rTop = rCursor;
      const rBot = rTop + flowH;
      ribbons.push({ lTop, lBot, rTop, rBot, color: rp.node.color ?? 'var(--muted-foreground)' });
      leftCursors[i] = lBot;
      rCursor = rBot;
    }
  }

  const ribbonPath = (r: { lTop: number; lBot: number; rTop: number; rBot: number }) =>
    `M ${leftEdge} ${r.lTop.toFixed(2)} ` +
    `C ${midA} ${r.lTop.toFixed(2)}, ${midB} ${r.rTop.toFixed(2)}, ${rightEdge} ${r.rTop.toFixed(2)} ` +
    `L ${rightEdge} ${r.rBot.toFixed(2)} ` +
    `C ${midB} ${r.rBot.toFixed(2)}, ${midA} ${r.lBot.toFixed(2)}, ${leftEdge} ${r.lBot.toFixed(2)} Z`;

  return (
    <svg aria-hidden width={width} height={height} viewBox={`0 0 ${width} ${height}`} className={className} preserveAspectRatio="none">
      {ribbons.map((r, i) => (
        <path key={i} d={ribbonPath(r)} style={{ fill: r.color, opacity: 0.32 }} />
      ))}
      {leftPositions.map((lp, i) => (
        <rect
          key={`l-${i}`}
          x={0}
          y={lp.top}
          width={nodeWidth}
          height={lp.height}
          style={{ fill: lp.node.color ?? 'var(--foreground)' }}
        />
      ))}
      {rightPositions.map((rp, i) => (
        <rect
          key={`r-${i}`}
          x={width - nodeWidth}
          y={rp.top}
          width={nodeWidth}
          height={rp.height}
          style={{ fill: rp.node.color ?? 'var(--muted-foreground)' }}
        />
      ))}
    </svg>
  );
}

/**
 * GitHub-contribution-style heatmap: one cell per day, rows = day-of-week,
 * columns = week. Intensity scales linearly from `emptyColor` (value ≤ 0) to
 * fully-saturated `color` (value = max).
 */
export function CalendarHeatmap({
  values,
  cellSize = 11,
  gap = 2,
  emptyColor = 'var(--secondary)',
  color = 'var(--primary)',
  className,
}: CalendarHeatmapProps) {
  if (!values.length) return null;
  const max = Math.max(...values.map((v) => v.value), 0);
  const firstDow = new Date(`${values[0].date}T00:00`).getDay();
  const cols = Math.ceil((firstDow + values.length) / 7);
  const w = cols * (cellSize + gap) - gap;
  const h = 7 * (cellSize + gap) - gap;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} width={w} height={h} className={className} aria-hidden>
      {values.map((v, i) => {
        const idx = firstDow + i;
        const x = Math.floor(idx / 7) * (cellSize + gap);
        const y = (idx % 7) * (cellSize + gap);
        const t = max > 0 && v.value > 0 ? Math.min(1, v.value / max) : 0;
        return (
          <rect
            key={v.date}
            x={x}
            y={y}
            width={cellSize}
            height={cellSize}
            rx={2}
            fill={t === 0 ? emptyColor : color}
            opacity={t === 0 ? 1 : 0.25 + 0.75 * t}
          >
            <title>{v.date}: {v.value.toFixed(2)}</title>
          </rect>
        );
      })}
    </svg>
  );
}
