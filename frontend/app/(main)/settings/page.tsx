'use client';

import { Icon, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton } from '@/components/MobileComponents';
import { SettingsItem } from '@/components/SettingsItem';
import { ThemeToggle } from '@/components/theme-toggle';
import { LedgerSwitcher } from '@/components/ledger-switcher';
import { useCurrency, type Currency } from '@/components/currency-provider';
import { useBackup } from '@/components/sqlite-backup-provider';
import { useFinanceStore } from '@/lib/store';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';
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

export default function SettingsPage() {
  const { currency, setCurrency } = useCurrency();
  const reset = useFinanceStore((s) => s.reset);
  const backup = useBackup();

  return (
    <MobilePage>
      <ScreenHeader title="Settings" trailing={<IconButton icon="search" aria-label="Search" />} />

      <div className="flex items-center gap-3.5 px-5 pb-[22px]">
        <MerchantGlyph name="Alex Morgan" size={64} bg="var(--primary)" fg="var(--primary-foreground)" />
        <div className="flex-1">
          <div className="font-serif text-[22px] -tracking-[0.3px]">Alex Morgan</div>
          <div className="text-muted-foreground text-xs">Personal plan</div>
        </div>
      </div>

      <div className="px-5 pb-28">
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
          Preferences
        </div>
        <SettingsItem item={{ label: 'Categories', value: '8 active', icon: 'tag' }} />
        <SettingsItem item={{ label: 'Notifications', toggle: true, icon: 'bell' }} />

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          Appearance
        </div>
        <Row icon="sparkle" label="Theme">
          <ThemeToggle />
        </Row>
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

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          Data
        </div>
        <Row icon="sync" label="Sample data">
          <Button
            variant="outline"
            size="sm"
            onClick={() => {
              reset();
              toast.success('Sample data restored');
            }}
          >
            Reset
          </Button>
        </Row>
        <div className="text-muted-foreground pt-2 text-xs">
          Your changes are saved on this device. Reset restores the original sample data.
        </div>

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          Database
        </div>
        <Row icon="doc" label="Database file (server)">
          <span className="text-muted-foreground max-w-[60%] truncate text-right font-mono text-[11px]">
            {backup.serverPath ?? '…'}
          </span>
        </Row>
        <Row icon="download" label="Export a copy">
          <Button variant="outline" size="sm" onClick={() => void backup.download()}>
            Download .db
          </Button>
        </Row>
        <Row icon="upload" label="Import database">
          <Button variant="outline" size="sm" disabled>
            Disabled
          </Button>
        </Row>
        <div className="text-muted-foreground pt-2 text-xs">
          Your data is stored in a SQLite file on the server and synced automatically on every
          change. Export downloads a point-in-time copy; import is disabled while the server file is
          the source of truth.
        </div>
      </div>
    </MobilePage>
  );
}
