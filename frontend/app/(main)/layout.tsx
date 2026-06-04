'use client';

import { useState } from 'react';
import { usePathname } from 'next/navigation';
import { PageShell } from '@/components/PageShell';
import { LedgerSwitcher } from '@/components/ledger-switcher';
import { MAIN_TAB_CATALOG, useMobileTabs } from '@/components/mobile-tabs';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';

// The ledger-admin sections, previously a separate "Ledger admin" shell, now
// surfaced as a labeled group in the main sidebar (desktop). URLs are unchanged.
const LEDGER_TABS = [
  { id: 'pending', icon: 'doc', label: 'Pending', path: '/pending' },
  { id: 'merchants', icon: 'bag', label: 'Merchants', path: '/merchants' },
  { id: 'categories', icon: 'tag', label: 'Categories', path: '/categories' },
  { id: 'tags', icon: 'tags', label: 'Tags', path: '/tags' },
];

// The pinned center button opens the add-expense sheet (see PageShell) rather
// than navigating, so it sits between the user-chosen sections.
const ADD_TAB = { id: 'add', icon: 'plus', label: 'Add', path: '/add', pinned: true };

export default function MainLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const { tabs: mobileSections } = useMobileTabs();
  const { activeId } = useLedger();
  const hasPending = useFinanceStore((s) =>
    s.transactions.some((t) => t.pending && (t.ledgerId ?? 'personal') === activeId),
  );

  const activeTab = pathname.split('/')[1] || 'accounts';

  const ledgerGroup = {
    label: 'Ledger',
    tabs: LEDGER_TABS.map((t) => (t.id === 'pending' ? { ...t, warnDot: hasPending } : t)),
  };

  // Add sits in the middle of the bar, flanked by the chosen sections.
  const mid = Math.ceil(mobileSections.length / 2);
  const mobileTabs = [...mobileSections.slice(0, mid), ADD_TAB, ...mobileSections.slice(mid)];

  return (
    <PageShell
      brand={{ glyph: 'F', label: 'Finch', toggleable: true }}
      tabs={MAIN_TAB_CATALOG}
      navGroups={[ledgerGroup]}
      mobileTabs={mobileTabs}
      activeTab={activeTab}
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