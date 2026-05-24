'use client';

import { usePathname } from 'next/navigation';
import { useTweaks } from './TweaksContext';
import { MobileTabBar } from './MobileComponents';

interface Tab {
  id: string;
  icon?: string;
  label: string;
  path?: string;
  pinned?: boolean;
}

interface MobileLayoutProps {
  children: React.ReactNode;
  tabs?: Tab[];
  active?: string;
}

export function MobileLayout({ children, tabs, active }: MobileLayoutProps) {
  const { theme: th } = useTweaks();
  const pathname = usePathname();

  const defaults = [
    { id: 'accounts',  icon: 'wallet',   label: 'Accounts' },
    { id: 'budgets',   icon: 'target',   label: 'Budgets' },
    { id: 'add',       icon: 'plus',     label: 'Add',      pinned: true },
    { id: 'scheduled', icon: 'calendar', label: 'Scheduled' },
    { id: 'insights',  icon: 'chart',   label: 'Insights' },
  ];

  return (
    <div style={{
      height: '100vh', background: th.paper, color: th.ink, fontFamily: th.body, position: 'relative', overflow: 'hidden'
    }}>
      <div style={{ height: '100%', overflowY: 'auto' }}>
        {children}
      </div>
      <MobileTabBar active={active ?? (pathname.replace('/', '') || 'accounts')} tabs={tabs ?? defaults}/>
    </div>
  );
}