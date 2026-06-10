// frontend/components/PageShell.tsx — the thin dispatcher that picks
// DesktopShell or MobileShell based on the viewport. Replaces the
// 366-line monolith with a ~30-line JS-conditional render. The
// previously-unused useIsDesktop hook (at components/use-is-desktop.ts)
// is now the gating mechanism.

'use client';

import { useIsDesktop } from './use-is-desktop';
import { DesktopShell } from './DesktopShell';
import { MobileShell } from './MobileShell';
import type { PageShellProps } from './shell-types';

export function PageShell(props: PageShellProps) {
  const isDesktop = useIsDesktop();
  return isDesktop ? <DesktopShell {...props} /> : <MobileShell {...props} />;
}

// Re-export the types so existing import paths (e.g.
// `import type { Tab } from '@/components/PageShell'`) still work.
export type { Tab, NavGroup, Brand, PageShellProps } from './shell-types';
