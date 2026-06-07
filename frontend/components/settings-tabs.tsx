'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { cn } from '@/lib/utils';

// Segmented switcher between the two settings surfaces. Each lives at its own
// route (/settings/account, /settings/ledger); /settings redirects to account.
const TAB_KEYS = [
  { href: '/settings/account', key: 'account' as const },
  { href: '/settings/ledger', key: 'ledger' as const },
];

export function SettingsTabs() {
  const pathname = usePathname();
  const t = useTranslations('settingsTabs');
  return (
    <div className="bg-secondary mb-5 inline-flex rounded-full p-1">
      {TAB_KEYS.map((tab) => {
        const active = pathname === tab.href || pathname.startsWith(`${tab.href}/`);
        return (
          <Link
            key={tab.href}
            href={tab.href}
            aria-current={active ? 'page' : undefined}
            className={cn(
              'rounded-full px-4 py-1.5 text-[13px] font-medium transition-colors',
              active
                ? 'bg-background text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground',
            )}
          >
            {t(tab.key)}
          </Link>
        );
      })}
    </div>
  );
}
