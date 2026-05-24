'use client';

import { usePathname } from 'next/navigation';
import { PageShell } from '@/components/PageShell';

const LEDGER_TABS = [
  { id: 'pending',   icon: 'doc',   label: 'Pending',   path: '/pending' },
  { id: 'transfers', icon: 'split', label: 'Transfers', path: '/transfers' },
  { id: 'merchants', icon: 'bag',   label: 'Merchants', path: '/merchants' },
  { id: 'recurring', icon: 'sync',  label: 'Recurring', path: '/recurring' },
];

const LEDGER_MOBILE_TABS = [
  { id: 'pending',   icon: 'doc',   label: 'Pending' },
  { id: 'transfers', icon: 'split', label: 'Transfers' },
  { id: 'merchants', icon: 'bag',   label: 'Merchants' },
  { id: 'recurring', icon: 'sync',  label: 'Recurring' },
];

const BOTTOM_LINKS = [
  { icon: 'arrow-l', label: 'Back to app', path: '/accounts' },
];

export default function LedgerLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const activeTab = pathname.replace('/', '') || 'pending';

  return (
    <PageShell
      mode="split"
      brand={{ glyph: 'L', label: 'Ledger' }}
      tabs={LEDGER_TABS}
      mobileTabs={LEDGER_MOBILE_TABS}
      activeTab={activeTab}
      bottomLinks={BOTTOM_LINKS}
      sidebarOpen={true}
    >
      <div style={{ padding: '20px 32px' }}>
        <div style={{ fontFamily: 'var(--font-display)', fontSize: 24, letterSpacing: -0.5 }}>Ledger Admin</div>
      </div>
      {children}
    </PageShell>
  );
}