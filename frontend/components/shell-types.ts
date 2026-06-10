// frontend/components/shell-types.ts — shared types for the DesktopShell
// and MobileShell components. Extracted from PageShell.tsx:22-98 (the
// original types lived inline in the file). The Tab shape is used by
// the catalog in components/mobile-tabs.ts; the NavGroup shape is used
// by the consumer in app/(main)/layout.tsx.

import type { ReactNode } from 'react';

export interface Tab {
  id: string;
  icon: string;
  label: string;
  path?: string;
  pinned?: boolean;
  warnDot?: boolean;
}

export interface NavGroup {
  label: string;
  tabs: Tab[];
}

export interface Brand {
  glyph?: string;
  label: string;
  toggleable?: boolean;
}

export interface PageShellProps {
  children: ReactNode;
  tabs?: Tab[];
  navGroups?: NavGroup[];
  mobileTabs?: Tab[];
  activeTab?: string;
  brand?: Brand;
  user?: { name: string; label: string };
  sidebarOpen?: boolean;
  onSidebarToggle?: () => void;
  headerTitle?: string;
  showAdd?: boolean;
  sidebarFooter?: ReactNode;
}
