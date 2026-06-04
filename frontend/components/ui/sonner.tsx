'use client';

import { useTheme } from 'next-themes';
import { Toaster as Sonner, type ToasterProps } from 'sonner';

import { useIsDesktop } from '@/components/use-is-desktop';

function Toaster({ ...props }: ToasterProps) {
  const { theme = 'system' } = useTheme();
  const isDesktop = useIsDesktop();

  // Toasts are a desktop-only affordance: on mobile they render full-width over
  // the fixed bottom tab bar, so we suppress them there. `toast()` calls become
  // visual no-ops without a mounted Toaster.
  if (!isDesktop) return null;

  return (
    <Sonner
      theme={theme as ToasterProps['theme']}
      className="toaster group"
      style={
        {
          '--normal-bg': 'var(--popover)',
          '--normal-text': 'var(--popover-foreground)',
          '--normal-border': 'var(--border)',
        } as React.CSSProperties
      }
      {...props}
    />
  );
}

export { Toaster };
