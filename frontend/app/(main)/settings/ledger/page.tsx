'use client';

import { useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { Icon } from '@/components/primitives';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { SettingsTabs } from '@/components/settings-tabs';
import { LedgerSwitcher } from '@/components/ledger-switcher';
import { ExchangeRates } from '@/components/exchange-rates';
import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
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
  const { activeId, active } = useLedger();
  const categoryCount = useFinanceStore(
    (s) => s.categories.filter((c) => c.ledgerId === activeId).length,
  );
  const txnCount = useFinanceStore(
    (s) => s.transactions.filter((t) => (t.ledgerId ?? 'personal') === activeId).length,
  );
  const changeLedgerBase = useFinanceStore((s) => s.changeLedgerBase);

  const [pendingBase, setPendingBase] = useState<string | null>(null);
  const confirmChange = () => {
    if (!pendingBase) return;
    changeLedgerBase(activeId, pendingBase);
    toast.success(`Base currency changed to ${pendingBase}`, {
      description: `${txnCount} transactions reconverted.`,
    });
    setPendingBase(null);
  };

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
        <Row icon="coins" label="Base currency">
          <Select
            value={active.base}
            onValueChange={(v) => {
              if (v !== active.base) setPendingBase(v);
            }}
          >
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
        <div className="text-muted-foreground pt-2 text-xs">
          Reporting currency for this ledger. Changing it rewrites every locked
          conversion in {txnCount.toLocaleString()} transaction{txnCount === 1 ? '' : 's'}
          {' '}using the rate on each transaction&rsquo;s own date.
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

      <Dialog open={!!pendingBase} onOpenChange={(o) => !o && setPendingBase(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Change base currency to {pendingBase}?</DialogTitle>
            <DialogDescription>
              Every locked <span className="font-mono">amount_base</span> in this ledger
              ({txnCount.toLocaleString()} transactions) will be re-converted under
              the new base, using the rate on each transaction&rsquo;s own date.
              Account balances are then re-derived. Reversible by switching back.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={confirmChange}>Change base</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
