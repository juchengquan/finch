'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { PALETTES, FONT_PAIRS, DENSITY, DEFAULT_TWEAKS } from '@/lib/theme';

interface Theme {
  paper: string;
  paperAlt: string;
  card: string;
  ink: string;
  ink2: string;
  muted: string;
  line: string;
  accent: string;
  accent2: string;
  pos: string;
  neg: string;
  warn: string;
  display: string;
  body: string;
  mono: string;
  currency: 'USD' | 'EUR' | 'GBP' | 'JPY';
}

interface TweaksContextType {
  tweaks: typeof DEFAULT_TWEAKS;
  setTweak: (key: keyof typeof DEFAULT_TWEAKS, value: string) => void;
  theme: Theme;
}

const TweaksContext = createContext<TweaksContextType | null>(null);

export function TweaksProvider({ children }: { children: ReactNode }) {
  const [tweaks, setTweaks] = useState(DEFAULT_TWEAKS);

  const theme: Theme = {
    ...(PALETTES[tweaks.palette as keyof typeof PALETTES] || PALETTES.warm),
    ...(FONT_PAIRS[tweaks.fonts as keyof typeof FONT_PAIRS] || FONT_PAIRS.editorial),
    ...(DENSITY[tweaks.density as keyof typeof DENSITY] || DENSITY.regular),
    currency: tweaks.currency as 'USD' | 'EUR' | 'GBP' | 'JPY',
  };

  useEffect(() => {
    const root = document.documentElement;
    const palette = PALETTES[tweaks.palette as keyof typeof PALETTES] || PALETTES.warm;
    const fonts = FONT_PAIRS[tweaks.fonts as keyof typeof FONT_PAIRS] || FONT_PAIRS.editorial;
    const density = DENSITY[tweaks.density as keyof typeof DENSITY] || DENSITY.regular;

    root.style.setProperty('--paper', palette.paper);
    root.style.setProperty('--paper-alt', palette.paperAlt);
    root.style.setProperty('--card', palette.card);
    root.style.setProperty('--ink', palette.ink);
    root.style.setProperty('--ink2', palette.ink2);
    root.style.setProperty('--muted', palette.muted);
    root.style.setProperty('--line', palette.line);
    root.style.setProperty('--accent', palette.accent);
    root.style.setProperty('--accent2', palette.accent2);
    root.style.setProperty('--pos', palette.pos);
    root.style.setProperty('--neg', palette.neg);
    root.style.setProperty('--warn', palette.warn);

    root.style.setProperty('--font-display', fonts.display);
    root.style.setProperty('--font-body', fonts.body);
    root.style.setProperty('--font-mono', fonts.mono);

    root.style.setProperty('--density-row', `${density.row}px`);
    root.style.setProperty('--density-gap', `${density.gap}px`);
    root.style.setProperty('--density-pad', `${density.pad}px`);
    root.style.setProperty('--density-fs', `${density.fs}px`);

    root.setAttribute('data-palette', tweaks.palette);
    root.setAttribute('data-density', tweaks.density);
  }, [tweaks.palette, tweaks.fonts, tweaks.density]);

  const setTweak = (key: keyof typeof DEFAULT_TWEAKS, value: string) => {
    setTweaks(prev => ({ ...prev, [key]: value }));
  };

  return (
    <TweaksContext.Provider value={{ tweaks, setTweak, theme }}>
      {children}
    </TweaksContext.Provider>
  );
}

export function useTweaks() {
  const ctx = useContext(TweaksContext);
  if (!ctx) throw new Error('useTweaks must be used within TweaksProvider');
  return ctx;
}