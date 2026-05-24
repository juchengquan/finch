'use client';

import { useTweaks } from './TweaksContext';
import { MobileTabBar } from './MobileComponents';

interface Tab {
  id: string;
  icon: string;
  label: string;
}

interface LedgerMobilePageProps {
  children: React.ReactNode;
  header?: React.ReactNode;
}

export function LedgerMobilePage({ children, header }: LedgerMobilePageProps) {
  const { theme: th } = useTweaks();

  const LEDGER_MOBILE_TABS = [
    { id: 'pending',   icon: 'doc',   label: 'Pending' },
    { id: 'transfers', icon: 'split', label: 'Transfers' },
    { id: 'merchants', icon: 'bag',   label: 'Merchants' },
    { id: 'recurring', icon: 'sync',  label: 'Recurring' },
  ];

  return (
    <div style={{
      height: '100dvh', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative', overflow: 'hidden'
    }}>
      {header && (
        <div style={{ position: 'sticky', top: 0, zIndex: 100, background: th.paper }}>
          {header}
        </div>
      )}
      <div style={{ height: 'calc(100% - 88px)', overflowY: 'auto' }}>
        {children}
      </div>
      <MobileTabBar active="pending" tabs={LEDGER_MOBILE_TABS}/>
    </div>
  );
}