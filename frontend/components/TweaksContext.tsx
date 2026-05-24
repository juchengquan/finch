'use client';

import { createContext, useContext, useState, ReactNode } from 'react';
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