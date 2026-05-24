'use client';

import Link from 'next/link';
import { useState } from 'react';
import { usePathname } from 'next/navigation';
import { useTweaks } from './TweaksContext';
import { Icon } from './primitives';
import { Sidebar } from './MobileComponents';

interface Tab {
  id: string;
  icon: string;
  label: string;
  path: string;
}

interface DesktopLayoutProps {
  children: React.ReactNode;
  mainTabs?: Tab[];
  moreTabs?: Tab[];
  bottomLinks?: { icon: string; label: string; path: string; warnDot?: boolean }[];
}

export function DesktopLayout({ children, mainTabs, moreTabs, bottomLinks }: DesktopLayoutProps) {
  const { theme: th } = useTweaks();
  const pathname = usePathname();
  const [sidebarOpen, setSidebarOpen] = useState(true);

  const defaults = {
    mainTabs: [
      { id: 'accounts',  icon: 'wallet',   label: 'Accounts',  path: '/accounts' },
      { id: 'budgets',   icon: 'target',   label: 'Budgets',   path: '/budgets' },
      { id: 'scheduled', icon: 'calendar', label: 'Scheduled', path: '/scheduled' },
      { id: 'insights',  icon: 'chart',   label: 'Insights',   path: '/insights' },
    ],
    moreTabs: [
      { id: 'goals',          icon: 'sparkle',  label: 'Goals',          path: '/goals' },
      { id: 'subscriptions',  icon: 'sync',     label: 'Subscriptions',  path: '/subscriptions' },
      { id: 'reports',        icon: 'doc',      label: 'Reports',        path: '/reports' },
      { id: 'activity',       icon: 'clock',    label: 'Activity',       path: '/activity' },
    ],
    bottomLinks: [
      { icon: 'cog',    label: 'Settings', path: '/settings' },
      { icon: 'bell',   label: 'Pending',   path: '/pending',  warnDot: true },
    ],
  };

  return (
    <div style={{
      height: '100vh', background: th.paper, color: th.ink, fontFamily: th.body,
      display: 'flex'
    }}>
      <Sidebar
        brand={{ glyph: 'F', label: 'Finch', toggleable: true }}
        mainTabs={mainTabs ?? defaults.mainTabs}
        moreTabs={moreTabs ?? defaults.moreTabs}
        bottomLinks={bottomLinks ?? defaults.bottomLinks}
        user={{ name: 'Alex Morgan', label: 'Personal' }}
        open={sidebarOpen}
        onToggle={() => setSidebarOpen(!sidebarOpen)}
      />

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, overflow: 'hidden' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '20px 32px', borderBottom: `1px solid ${th.line}`, gap: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, height: 36, padding: '0 14px', background: th.paperAlt, borderRadius: 18, color: th.muted, fontSize: 13, width: 240, cursor: 'pointer' }}>
              <Icon name="search" size={14}/>Search transactions…
            </div>
            <Link href="/add" style={{ display: 'flex', alignItems: 'center', gap: 8, height: 36, padding: '0 16px', background: th.ink, color: th.paper, borderRadius: 18, fontSize: 13, fontWeight: 500, cursor: 'pointer', textDecoration: 'none' }}>
              <Icon name="plus" size={14} stroke={2}/>Add expense
            </Link>
          </div>
        </div>

        <div style={{ flex: 1, overflowY: 'auto' }}>
          {children}
        </div>
      </div>
    </div>
  );
}