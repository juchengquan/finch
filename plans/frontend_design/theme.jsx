// Design tokens — warm editorial palette. Cream paper, ink, terracotta.
// Tweaks override these at runtime via the useTweaks hook.

const PALETTES = {
  warm: {
    name: 'Warm editorial',
    paper:    '#f5f1ea',
    paperAlt: '#ece5d9',
    card:     '#faf7f1',
    ink:      '#1a1614',
    ink2:     '#3a322c',
    muted:    '#8a7e6e',
    line:     '#d8cfc1',
    accent:   '#c96442',
    accent2:  '#e07856',
    pos:      '#5e7d5e',
    neg:      '#c96442',
    warn:     '#c89a3e',
  },
  noir: {
    name: 'Noir',
    paper:    '#0e0d0c',
    paperAlt: '#1a1816',
    card:     '#1c1a17',
    ink:      '#f1ece2',
    ink2:     '#c9c0b1',
    muted:    '#7a7367',
    line:     '#2a2722',
    accent:   '#e07856',
    accent2:  '#c89a3e',
    pos:      '#9bb89b',
    neg:      '#e07856',
    warn:     '#d8b366',
  },
  forest: {
    name: 'Forest',
    paper:    '#f3f0e8',
    paperAlt: '#e6e0d2',
    card:     '#fbf8f1',
    ink:      '#1a2018',
    ink2:     '#3a4438',
    muted:    '#7a8478',
    line:     '#cdd3c4',
    accent:   '#3d6b46',
    accent2:  '#6b8a6b',
    pos:      '#3d6b46',
    neg:      '#a8533a',
    warn:     '#b88a3a',
  },
  indigo: {
    name: 'Indigo',
    paper:    '#f4f4f8',
    paperAlt: '#e8e8f0',
    card:     '#ffffff',
    ink:      '#0f1024',
    ink2:     '#2e3050',
    muted:    '#7a7c92',
    line:     '#d4d6e0',
    accent:   '#3a3aff',
    accent2:  '#8a8cff',
    pos:      '#1f8a5b',
    neg:      '#c83a3a',
    warn:     '#c89a3e',
  },
};

const FONT_PAIRS = {
  editorial: {
    name: 'Editorial',
    display: "'Instrument Serif', 'EB Garamond', Georgia, serif",
    body:    "'Inter', -apple-system, BlinkMacSystemFont, system-ui, sans-serif",
    mono:    "'JetBrains Mono', ui-monospace, 'SF Mono', monospace",
  },
  grotesk: {
    name: 'Grotesk',
    display: "'Space Grotesk', 'Inter', system-ui, sans-serif",
    body:    "'Space Grotesk', 'Inter', system-ui, sans-serif",
    mono:    "'JetBrains Mono', ui-monospace, monospace",
  },
  classic: {
    name: 'Classic',
    display: "'Inter', -apple-system, system-ui, sans-serif",
    body:    "'Inter', -apple-system, system-ui, sans-serif",
    mono:    "ui-monospace, 'SF Mono', monospace",
  },
  swiss: {
    name: 'Swiss',
    display: "'Inter Tight', 'Inter', system-ui, sans-serif",
    body:    "'Inter', system-ui, sans-serif",
    mono:    "'JetBrains Mono', ui-monospace, monospace",
  },
};

// Density scales — used by screens that opt in.
const DENSITY = {
  compact:  { row: 44, gap: 8,  pad: 12, fs: 13 },
  regular:  { row: 56, gap: 12, pad: 16, fs: 14 },
  roomy:    { row: 68, gap: 18, pad: 20, fs: 15 },
};

// Resolve theme tokens from tweaks state.
function useTheme(t) {
  return React.useMemo(() => {
    const pal = PALETTES[t.palette] || PALETTES.warm;
    const fonts = FONT_PAIRS[t.fonts] || FONT_PAIRS.editorial;
    const dens = DENSITY[t.density] || DENSITY.regular;
    return { ...pal, ...fonts, ...dens, currency: t.currency, chart: t.chart };
  }, [t.palette, t.fonts, t.density, t.currency, t.chart]);
}

Object.assign(window, { PALETTES, FONT_PAIRS, DENSITY, useTheme });
