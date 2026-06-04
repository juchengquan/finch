// Shared UI primitives — icons, small charts, building blocks.
// All theme-aware via the `th` object passed in.

// ─────────────────────────────────────────────────────────────
// Icons — simple, stroked, currentColor.
// ─────────────────────────────────────────────────────────────
function Icon({ name, size = 18, stroke = 1.5, style }) {
  const props = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: stroke, strokeLinecap: 'round', strokeLinejoin: 'round', style };
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

// ─────────────────────────────────────────────────────────────
// Money — formatted with a small currency mark in the right size.
// ─────────────────────────────────────────────────────────────
function Money({ value, currency, signed = false, big = false, mono = true, style }) {
  const s = fmtMoney(value, currency || 'USD');
  return <span style={{
    fontVariantNumeric: 'tabular-nums', fontFeatureSettings: '"tnum"',
    fontFamily: mono ? "'Inter', system-ui, sans-serif" : 'inherit',
    ...style,
  }}>{signed && value > 0 ? '+' : ''}{s}</span>;
}

// ─────────────────────────────────────────────────────────────
// Charts — all SVG, theme-aware via fg/bg/accent props.
// ─────────────────────────────────────────────────────────────

// Sparkline / area chart
function Sparkline({ values, width = 200, height = 50, color = '#c96442', fillOpacity = 0.12, stroke = 1.5 }) {
  const max = Math.max(...values, 1);
  const step = width / Math.max(values.length - 1, 1);
  const pts = values.map((v, i) => [i * step, height - (v / max) * (height - 4) - 2]);
  const d = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
  const fill = d + ` L${width} ${height} L0 ${height} Z`;
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      <path d={fill} fill={color} opacity={fillOpacity}/>
      <path d={d} fill="none" stroke={color} strokeWidth={stroke} strokeLinejoin="round" strokeLinecap="round"/>
    </svg>
  );
}

// Bar chart (vertical)
function BarChart({ values, labels, width = 280, height = 80, color = '#1a1614', highlight = '#c96442', muted = '#d8cfc1' }) {
  const max = Math.max(...values, 1);
  const n = values.length;
  const gap = 4;
  const bw = (width - gap * (n - 1)) / n;
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height + 14}`}>
      {values.map((v, i) => {
        const h = (v / max) * height;
        const x = i * (bw + gap);
        const isLast = i === n - 1;
        return (
          <g key={i}>
            <rect x={x} y={height - h} width={bw} height={h} fill={isLast ? highlight : muted} rx={1.5}/>
            {labels && <text x={x + bw / 2} y={height + 11} fontSize="9" fill={color} opacity="0.55" textAnchor="middle" fontFamily="inherit">{labels[i]}</text>}
          </g>
        );
      })}
    </svg>
  );
}

// Donut — categories
function Donut({ slices, size = 140, stroke = 22, gap = 2 }) {
  // slices: [{ value, color }]
  const total = slices.reduce((s, x) => s + x.value, 0) || 1;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  let acc = 0;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: 'rotate(-90deg)' }}>
      {slices.map((s, i) => {
        const len = (s.value / total) * c;
        const offset = -acc;
        acc += len;
        return (
          <circle key={i} cx={size / 2} cy={size / 2} r={r} fill="none"
            stroke={s.color} strokeWidth={stroke}
            strokeDasharray={`${Math.max(len - gap, 0.1)} ${c}`}
            strokeDashoffset={offset} />
        );
      })}
    </svg>
  );
}

// Stacked horizontal bar (one bar broken into segments)
function StackedBar({ slices, width = 280, height = 8, gap = 2, radius = 4 }) {
  const total = slices.reduce((s, x) => s + x.value, 0) || 1;
  let x = 0;
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      {slices.map((s, i) => {
        const w = Math.max((s.value / total) * width - (i < slices.length - 1 ? gap : 0), 0);
        const rect = <rect key={i} x={x} y={0} width={w} height={height} fill={s.color} rx={radius}/>;
        x += w + gap;
        return rect;
      })}
    </svg>
  );
}

// Calendar heatmap (cells)
function CalendarHeatmap({ values, color = '#c96442', muted = '#ede6d8', cols = 7, cell = 28, gap = 4 }) {
  const max = Math.max(...values, 1);
  const rows = Math.ceil(values.length / cols);
  const width = cols * (cell + gap) - gap;
  const height = rows * (cell + gap) - gap;
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      {values.map((v, i) => {
        const r = Math.floor(i / cols), c = i % cols;
        const opacity = v === 0 ? 0 : 0.15 + 0.85 * (v / max);
        return (
          <g key={i}>
            <rect x={c * (cell + gap)} y={r * (cell + gap)} width={cell} height={cell} fill={muted} rx={3}/>
            {v > 0 && <rect x={c * (cell + gap)} y={r * (cell + gap)} width={cell} height={cell} fill={color} opacity={opacity} rx={3}/>}
          </g>
        );
      })}
    </svg>
  );
}

// Stream / area chart (multiple series)
function AreaChart({ series, width = 280, height = 100, colors = ['#c96442','#1a1614'], smooth = true }) {
  const flat = series.flat();
  const max = Math.max(...flat, 1);
  const n = series[0].length;
  const step = width / Math.max(n - 1, 1);
  const path = (vals) => {
    const pts = vals.map((v, i) => [i * step, height - (v / max) * height]);
    if (!smooth) return pts.map((p, i) => (i ? 'L' : 'M') + p[0] + ' ' + p[1]).join(' ');
    let d = `M${pts[0][0]} ${pts[0][1]}`;
    for (let i = 1; i < pts.length; i++) {
      const [x1, y1] = pts[i - 1], [x2, y2] = pts[i];
      const mx = (x1 + x2) / 2;
      d += ` C${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}`;
    }
    return d;
  };
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      {series.map((s, i) => {
        const d = path(s);
        const fill = d + ` L${width} ${height} L0 ${height} Z`;
        return (
          <g key={i}>
            <path d={fill} fill={colors[i]} opacity="0.12"/>
            <path d={d} fill="none" stroke={colors[i]} strokeWidth="1.6" strokeLinejoin="round"/>
          </g>
        );
      })}
    </svg>
  );
}

// Ring progress (single)
function Ring({ value, max = 100, size = 48, stroke = 5, color = '#c96442', track = '#e8dfd0', children }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const pct = Math.max(0, Math.min(1, value / max));
  return (
    <div style={{ position: 'relative', width: size, height: size, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={track} strokeWidth={stroke}/>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeWidth={stroke}
          strokeLinecap="round" strokeDasharray={`${pct * c} ${c}`}/>
      </svg>
      {children && <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{children}</div>}
    </div>
  );
}

// Merchant glyph — circle with first letter (no real logos used)
function MerchantGlyph({ name, size = 36, hue, bg, fg = '#1a1614' }) {
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

// Category dot
function CatDot({ hue, size = 8 }) {
  return <span style={{ display: 'inline-block', width: size, height: size, borderRadius: '50%', background: `oklch(0.65 0.13 ${hue})` }}/>;
}

Object.assign(window, { Icon, Money, Sparkline, BarChart, Donut, StackedBar, CalendarHeatmap, AreaChart, Ring, MerchantGlyph, CatDot });
