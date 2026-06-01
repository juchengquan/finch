'use client';

import Link from 'next/link';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { SettingsTabs } from '@/components/settings-tabs';
import { LedgerSwitcher } from '@/components/ledger-switcher';
import { ExchangeRates } from '@/components/exchange-rates';
import { useCurrency, type Currency } from '@/components/currency-provider';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

const CURRENCIES: Currency[] = ['USD', 'EUR', 'GBP', 'JPY', 'SGD', 'CNY'];

function Row({ icon, label, children }: { icon: string; label: string; children: React.ReactNode }) {
  return (
    <div className="border-border flex items-center gap-3.5 border-b py-3.5">
      <div className="bg-secondary text-secondary-foreground flex size-[30px] shrink-0 items-center justify-center rounded-full">
        <Icon name={icon} size={14} />
      </div>
      <div className="flex-1 text-sm">{label}</div>
      {children}
    </div>
  );
}

export default function LedgerSettingsPage() {
  const { currency, setCurrency } = useCurrency();
  const { activeId } = useLedger();
  const categoryCount = useFinanceStore(
    (s) => s.categories.filter((c) => c.ledgerId === activeId).length,
  );

  return (
    <MobilePage>
      <ScreenHeader title="Settings" trailing={<SearchButton />} />

      <div className="px-5 pb-28">
        <SettingsTabs />

        <div className="text-muted-foreground pb-2 font-mono text-[10px] tracking-wider uppercase">
          Active ledger
        </div>
        <div className="md:hidden">
          <LedgerSwitcher />
        </div>
        <div className="text-muted-foreground hidden pt-1 text-xs md:block">
          Switch ledgers from the sidebar.
        </div>

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          This ledger
        </div>
        <Row icon="wallet" label="Display currency">
          <Select value={currency} onValueChange={(v) => setCurrency(v as Currency)}>
            <SelectTrigger size="sm" className="w-24">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {CURRENCIES.map((c) => (
                <SelectItem key={c} value={c}>
                  {c}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Row>
        <Row icon="tag" label="Categories">
          <Link href="/categories" className="text-muted-foreground hover:text-foreground inline-flex items-center gap-1 text-[12px]">
            {categoryCount} {categoryCount === 1 ? 'category' : 'categories'}
            <Icon name="chev" size={11} />
          </Link>
        </Row>

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          Exchange rates
        </div>
        <ExchangeRates />
      </div>
    </MobilePage>
  );
}
