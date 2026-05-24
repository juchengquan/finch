'use client';

import { useState } from 'react';
import { usePathname } from 'next/navigation';
import Link from 'next/link';
import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { MobileTabBar, Sidebar } from '@/components/MobileComponents';

const MAIN_TABS = [
  { id: 'accounts',  icon: 'wallet',   label: 'Accounts',  path: '/accounts' },
  { id: 'budgets',   icon: 'target',   label: 'Budgets',   path: '/budgets' },
  { id: 'scheduled', icon: 'calendar', label: 'Scheduled', path: '/scheduled' },
  { id: 'insights',  icon: 'chart',   label: 'Insights',   path: '/insights' },
];

const MORE_TABS = [
  { id: 'goals',          icon: 'sparkle',  label: 'Goals',          path: '/goals' },
  { id: 'subscriptions',  icon: 'sync',     label: 'Subscriptions',  path: '/subscriptions' },
  { id: 'reports',        icon: 'doc',      label: 'Reports',        path: '/reports' },
  { id: 'activity',       icon: 'clock',    label: 'Activity',       path: '/activity' },
];

const BOTTOM_LINKS = [
  { icon: 'cog',    label: 'Settings', path: '/settings' },
  { icon: 'bell',   label: 'Pending',   path: '/pending',  warnDot: true },
];

const MAIN_MOBILE_TABS = [
  { id: 'accounts',  icon: 'wallet',   label: 'Accounts' },
  { id: 'budgets',   icon: 'target',   label: 'Budgets' },
  { id: 'add',       icon: 'plus',     label: 'Add',      pinned: true },
  { id: 'scheduled', icon: 'calendar', label: 'Scheduled' },
  { id: 'insights',  icon: 'chart',   label: 'Insights' },
];

export default function MainLayout({ children }: { children: React.ReactNode }) {
  const { theme: th } = useTweaks();
  const pathname = usePathname();
  const [sidebarOpen, setSidebarOpen] = useState(true);

  return (
    <>
      {/* Mobile shell */}
      <div className="mobile-shell" style={{
        height: '100dvh', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative', overflow: 'hidden'
      }}>
        <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 88 }}>
          {children}
        </div>
        <MobileTabBar active={pathname.replace('/', '') || 'accounts'} tabs={MAIN_MOBILE_TABS}/>
      </div>

      {/* Desktop shell */}
      <div className="desktop-shell" style={{
        height: '100vh', background: th.paper, color: th.ink, fontFamily: th.body
      }}>
        <Sidebar
          brand={{ glyph: 'F', label: 'Finch', toggleable: true }}
          mainTabs={MAIN_TABS}
          moreTabs={MORE_TABS}
          bottomLinks={BOTTOM_LINKS}
          user={{ name: 'Alex Morgan', label: 'Personal' }}
          open={sidebarOpen}
          onToggle={() => setSidebarOpen(!sidebarOpen)}
        />

        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '20px 32px', borderBottom: `1px solid ${th.line}`, gap: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            </div>
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
    </>
  );
}
