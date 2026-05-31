'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/utils';

// Segmented switcher between the two settings surfaces. Each lives at its own
// route (/settings/account, /settings/ledger); /settings redirects to account.
const TABS = [
  { href: '/settings/account', label: 'Account' },
  { href: '/settings/ledger', label: 'Ledger' },
  { href: '/settings/devices', label: 'Devices' },
];

export function SettingsTabs() {
  const pathname = usePathname();
  return (
    <div className="bg-secondary mb-5 inline-flex rounded-full p-1">
      {TABS.map((t) => {
        const active = pathname === t.href || pathname.startsWith(`${t.href}/`);
        return (
          <Link
            key={t.href}
            href={t.href}
            aria-current={active ? 'page' : undefined}
            className={cn(
              'rounded-full px-4 py-1.5 text-[13px] font-medium transition-colors',
              active
                ? 'bg-background text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            )}
          >
            {t.label}
          </Link>
        );
      })}
    </div>
  );
}
