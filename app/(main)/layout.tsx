'use client';

import { useState } from 'react';
import { usePathname } from 'next/navigation';
import { PageShell } from '@/components/PageShell';
import { LedgerSwitcher } from '@/components/ledger-switcher';

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
  { icon: 'bell',   label: 'Pending',   path: '/pending',  warnDot: true },
];

const MAIN_MOBILE_TABS = [
  { id: 'accounts',  icon: 'wallet',   label: 'Accounts',  path: '/accounts' },
  { id: 'budgets',   icon: 'target',   label: 'Budgets',   path: '/budgets' },
  { id: 'add',       icon: 'plus',     label: 'Add',      path: '/add', pinned: true },
  { id: 'scheduled', icon: 'calendar', label: 'Scheduled', path: '/scheduled' },
  { id: 'insights',  icon: 'chart',    label: 'Insights',  path: '/insights' },
];

export default function MainLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const [sidebarOpen, setSidebarOpen] = useState(true);

  const activeTab = pathname.split('/')[1] || 'accounts';

  return (
    <PageShell
      brand={{ glyph: 'F', label: 'Finch', toggleable: true }}
      tabs={[...MAIN_TABS, ...MORE_TABS]}
      mobileTabs={MAIN_MOBILE_TABS}
      activeTab={activeTab}
      bottomLinks={BOTTOM_LINKS}
      user={{ name: 'Alex Morgan', label: 'Personal' }}
      sidebarOpen={sidebarOpen}
      onSidebarToggle={() => setSidebarOpen(!sidebarOpen)}
      showAdd
      sidebarFooter={<LedgerSwitcher sidebarOpen={sidebarOpen} />}
    >
      {children}
    </PageShell>
  );
}