'use client';

import { useState } from 'react';
import { usePathname } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { PageShell } from '@/components/PageShell';
import { LedgerSwitcher } from '@/components/ledger-switcher';
import { useMainTabCatalog, useMobileTabs } from '@/components/mobile-tabs';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';

// The ledger-admin sections, previously a separate "Ledger admin" shell, now
// surfaced as a labeled group in the main sidebar (desktop). URLs are unchanged.
const LEDGER_TAB_SEEDS = [
  { id: 'pending', icon: 'doc', path: '/pending' },
  { id: 'merchants', icon: 'bag', path: '/merchants' },
  { id: 'categories', icon: 'tag', path: '/categories' },
  { id: 'tags', icon: 'tags', path: '/tags' },
  { id: 'rules', icon: 'sparkle', path: '/rules' },
];

export default function MainLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const mainTabs = useMainTabCatalog();
  const { tabs: mobileSections } = useMobileTabs();
  const { activeId } = useLedger();
  const tNav = useTranslations('nav');
  const tShell = useTranslations('shell');
  const hasPending = useFinanceStore((s) =>
    s.transactions.some((t) => t.pending && (t.ledgerId ?? 'personal') === activeId),
  );

  const activeTab = pathname.split('/')[1] || 'accounts';

  const ledgerGroup = {
    label: tNav('ledgerGroup'),
    tabs: LEDGER_TAB_SEEDS.map((t) => ({
      ...t,
      label: tNav(t.id),
      ...(t.id === 'pending' ? { warnDot: hasPending } : {}),
    })),
  };

  // The pinned center button opens the add-expense dialog (see PageShell) rather
  // than navigating, so it sits between the user-chosen sections.
  const addTab = { id: 'add', icon: 'plus', label: tNav('add'), pinned: true };

  // Add sits in the middle of the bar, flanked by the chosen sections.
  const mid = Math.ceil(mobileSections.length / 2);
  const mobileTabs = [...mobileSections.slice(0, mid), addTab, ...mobileSections.slice(mid)];

  return (
    <PageShell
      brand={{ glyph: 'F', label: tShell('brand'), toggleable: true }}
      tabs={mainTabs}
      navGroups={[ledgerGroup]}
      mobileTabs={mobileTabs}
      activeTab={activeTab}
      user={{ name: 'Alex Morgan', label: tShell('userLabel') }}
      sidebarOpen={sidebarOpen}
      onSidebarToggle={() => setSidebarOpen(!sidebarOpen)}
      showAdd
      sidebarFooter={<LedgerSwitcher sidebarOpen={sidebarOpen} />}
    >
      {children}
    </PageShell>
  );
}