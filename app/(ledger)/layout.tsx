'use client';

import { usePathname } from 'next/navigation';
import Link from 'next/link';
import { useTweaks } from '@/components/TweaksContext';
import { Icon } from '@/components/primitives';
import { MobileTabBar, Sidebar } from '@/components/MobileComponents';

const LEDGER_TABS = [
  { id: 'pending',   icon: 'doc',  label: 'Pending',   path: '/pending' },
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
  const { theme: th } = useTweaks();
  const pathname = usePathname();

  return (
    <>
      {/* Mobile shell */}
      <div className="mobile-shell" style={{
        height: '100dvh', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative', overflow: 'hidden'
      }}>
        <div style={{ height: '100%', overflowY: 'auto', paddingBottom: 88 }}>
          {children}
        </div>
        <MobileTabBar active={pathname.replace('/', '') || 'pending'} tabs={LEDGER_MOBILE_TABS}/>
      </div>

      {/* Desktop shell */}
      <div className="desktop-shell" style={{
        height: '100vh', background: th.paper, color: th.ink, fontFamily: th.body
      }}>
        <Sidebar
          brand={{ glyph: 'L', glyphBg: th.ink, label: 'Ledger' }}
          mainTabs={LEDGER_TABS}
          bottomLinks={BOTTOM_LINKS}
          open={true}
        />

        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, overflow: 'hidden' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '20px 32px', borderBottom: `1px solid ${th.line}`, gap: 16 }}>
            <div style={{ fontFamily: th.display, fontSize: 24, letterSpacing: -0.5 }}>Ledger Admin</div>
          </div>
          <div style={{ flex: 1, overflowY: 'auto' }}>
            {children}
          </div>
        </div>
      </div>
    </>
  );
}
