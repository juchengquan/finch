'use client';

import { usePathname } from 'next/navigation';
import { PageShell } from '@/components/PageShell';
import { LedgerSwitcher } from '@/components/ledger-switcher';

const LEDGER_TABS = [
  { id: 'pending',   icon: 'doc',   label: 'Pending',   path: '/pending' },
  { id: 'transfers', icon: 'split', label: 'Transfers', path: '/transfers' },
  { id: 'merchants', icon: 'bag',   label: 'Merchants', path: '/merchants' },
  { id: 'recurring', icon: 'sync',  label: 'Recurring', path: '/recurring' },
  { id: 'categories', icon: 'tag', label: 'Categories', path: '/categories' },
  { id: 'system', icon: 'cog', label: 'System', path: '/system' },
];

const LEDGER_MOBILE_TABS = [
  { id: 'pending',   icon: 'doc',   label: 'Pending' },
  { id: 'transfers', icon: 'split', label: 'Transfers' },
  { id: 'merchants', icon: 'bag',   label: 'Merchants' },
  { id: 'recurring', icon: 'sync',  label: 'Recurring' },
  { id: 'categories', icon: 'tag', label: 'Categories' },
];

const BOTTOM_LINKS = [
  { icon: 'arrow-l', label: 'Back to app', path: '/accounts' },
];

export default function LedgerLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const activeTab = pathname.split('/')[1] || 'pending';

  return (
    <PageShell
      brand={{ glyph: 'L', label: 'Ledger' }}
      tabs={LEDGER_TABS}
      mobileTabs={LEDGER_MOBILE_TABS}
      activeTab={activeTab}
      bottomLinks={BOTTOM_LINKS}
      headerTitle="Ledger admin"
      sidebarFooter={<LedgerSwitcher />}
    >
      {children}
    </PageShell>
  );
}