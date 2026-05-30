'use client';

import { useState } from 'react';
import { usePathname } from 'next/navigation';
import { PageShell } from '@/components/PageShell';
import { LedgerSwitcher } from '@/components/ledger-switcher';
import { MAIN_TAB_CATALOG, useMobileTabs } from '@/components/mobile-tabs-provider';

const BOTTOM_LINKS = [
  { icon: 'bell',   label: 'Pending',   path: '/pending',  warnDot: true },
];

// The pinned center button opens the add-expense sheet (see PageShell) rather
// than navigating, so it sits between the user-chosen sections.
const ADD_TAB = { id: 'add', icon: 'plus', label: 'Add', path: '/add', pinned: true };

export default function MainLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const { tabs: mobileSections } = useMobileTabs();

  const activeTab = pathname.split('/')[1] || 'accounts';

  // Add sits in the middle of the bar, flanked by the chosen sections.
  const mid = Math.ceil(mobileSections.length / 2);
  const mobileTabs = [...mobileSections.slice(0, mid), ADD_TAB, ...mobileSections.slice(mid)];

  return (
    <PageShell
      brand={{ glyph: 'F', label: 'Finch', toggleable: true }}
      tabs={MAIN_TAB_CATALOG}
      mobileTabs={mobileTabs}
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