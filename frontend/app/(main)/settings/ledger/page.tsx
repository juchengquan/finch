'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Chev, Check, Coins, Pencil, Tag, Trash, Wallet } from '@/components/icons';
import { MobilePage } from '@/components/mobile-page';
import { ScreenHeader } from '@/components/ui/screen-header';
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
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { cn } from '@/lib/utils';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

const CURRENCIES: Currency[] = ['USD', 'EUR', 'GBP', 'JPY', 'SGD', 'CNY'];

// Row.icon is a string short-name; resolve to the typed lucide component so
// the row template can stay declarative. Only the icons used in the ledger
// settings rows appear here; extend as new rows are added.
const ROW_ICON: Record<string, typeof Wallet> = {
  coins: Coins,
  wallet: Wallet,
  tag: Tag,
  pencil: Pencil,
  check: Check,
  trash: Trash,
};

function Row({ icon, label, children }: { icon: string; label: string; children: React.ReactNode }) {
  const Glyph = ROW_ICON[icon] ?? Wallet;
  return (
    <div className="border-border flex items-center gap-3.5 border-b py-3.5">
      <div className="bg-secondary text-secondary-foreground flex size-[30px] shrink-0 items-center justify-center rounded-full">
        <Glyph size={14} />
      </div>
      <div className="flex-1 text-sm">{label}</div>
      {children}
    </div>
  );
}

export default function LedgerSettingsPage() {
  const router = useRouter();
  const { currency, setCurrency } = useCurrency();
  const { ledgers, activeId, active, setActiveId } = useLedger();
  const tLedger = useTranslations('settings.ledger');
  const tAccount = useTranslations('settings.account');
  const tCommon = useTranslations('common');
  const categoryCount = useFinanceStore(
    (s) => s.categories.filter((c) => c.ledgerId === activeId).length,
  );
  const txnCount = useFinanceStore(
    (s) => s.transactions.filter((t) => (t.ledgerId ?? 'personal') === activeId).length,
  );
  const changeLedgerBase = useFinanceStore((s) => s.changeLedgerBase);
  const updateLedger = useFinanceStore((s) => s.updateLedger);
  const setDefaultLedger = useFinanceStore((s) => s.setDefaultLedger);
  const deleteLedger = useFinanceStore((s) => s.deleteLedger);
  const accountCount = useFinanceStore(
    (s) => s.accounts.filter((a) => a.ledgerId === activeId).length,
  );

  const [pendingBase, setPendingBase] = useState<string | null>(null);
  const [editOpen, setEditOpen] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);

  const confirmChange = () => {
    if (!pendingBase) return;
    changeLedgerBase(activeId, pendingBase);
    toast.success(tLedger('baseCurrencyToast', { currency: pendingBase }), {
      description: tLedger('baseCurrencyToastDescription', { count: txnCount }),
    });
    setPendingBase(null);
  };

  const onMakeDefault = () => {
    setDefaultLedger(activeId);
    toast.success(tLedger('defaultedToast', { name: active.name }));
  };

  const isLastLedger = ledgers.length <= 1;

  return (
    <MobilePage>
      <ScreenHeader title={tAccount('title')} trailing={<SearchButton />} />

      <div className="px-5 pb-28">
        <SettingsTabs />

        <div className="text-muted-foreground pb-2 font-mono text-[10px] tracking-wider uppercase">
          {tLedger('activeSection')}
        </div>
        <div className="md:hidden">
          <LedgerSwitcher />
        </div>
        <div className="text-muted-foreground hidden pt-1 text-xs md:block">
          {tLedger('switchHint')}
        </div>

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          {tLedger('thisLedgerSection')}
        </div>
        <Row icon="coins" label={tLedger('baseCurrency')}>
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
          {tLedger('baseCurrencyHint', { count: txnCount })}
        </div>

        <Row icon="wallet" label={tLedger('displayCurrency')}>
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
        <Row icon="tag" label={tLedger('categoriesRow')}>
          <Link href="/categories" className="text-muted-foreground hover:text-foreground inline-flex items-center gap-1 text-[12px]">
            {tLedger('categoriesCount', { count: categoryCount })}
            <Chev size={11} />
          </Link>
        </Row>
        <Row icon="pencil" label={tLedger('nameAppearance')}>
          <Button variant="outline" size="sm" onClick={() => setEditOpen(true)}>
            {tLedger('editButton')}
          </Button>
        </Row>
        {active.isDefault !== 1 && (
          <Row icon="check" label={tLedger('defaultLedgerRow')}>
            <Button variant="outline" size="sm" onClick={onMakeDefault}>
              {tLedger('makeDefaultButton')}
            </Button>
          </Row>
        )}

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          {tLedger('exchangeRatesSection')}
        </div>
        <ExchangeRates />

        <div className="text-muted-foreground pt-6 pb-2 font-mono text-[10px] tracking-wider uppercase">
          {tLedger('dangerZoneSection')}
        </div>
        <Row icon="trash" label={tLedger('deleteRow')}>
          <Button
            variant="outline"
            size="sm"
            disabled={isLastLedger}
            onClick={() => setDeleteOpen(true)}
            className={cn(!isLastLedger && 'text-destructive hover:text-destructive')}
          >
            {tLedger('deleteButton')}
          </Button>
        </Row>
        {isLastLedger && (
          <div className="text-muted-foreground pt-1 text-xs">
            {tLedger('lastLedgerHint')}
          </div>
        )}
      </div>

      <Dialog open={!!pendingBase} onOpenChange={(o) => !o && setPendingBase(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{tLedger('baseChangeDialog.title', { currency: pendingBase ?? '' })}</DialogTitle>
            <DialogDescription>
              {tLedger('baseChangeDialog.description', { count: txnCount })}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={confirmChange}>{tLedger('baseChangeDialog.confirm')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <EditLedgerDialog
        open={editOpen}
        onOpenChange={setEditOpen}
        ledgerId={activeId}
        currentName={active.name}
        currentColor={active.color}
        currentTagline={active.tagline}
        onSave={(patch) => {
          updateLedger(activeId, patch);
          toast.success(tLedger('editDialog.updatedToast'));
          setEditOpen(false);
        }}
      />

      <DeleteLedgerDialog
        open={deleteOpen}
        onOpenChange={setDeleteOpen}
        ledgerName={active.name}
        accountCount={accountCount}
        txnCount={txnCount}
        onConfirm={() => {
          const oldName = active.name;
          // Pre-pick a new active id from the remaining ledgers so the redirect
          // lands on something sensible after the projection updates.
          const next = ledgers.find((l) => l.id !== activeId);
          deleteLedger(activeId);
          if (next) setActiveId(next.id);
          toast.success(tLedger('deleteDialog.deletedToast', { name: oldName }));
          setDeleteOpen(false);
          // Navigate away from the deleted ledger's context.
          router.push('/');
        }}
      />
    </MobilePage>
  );
}

// Edit dialog. The form body is mounted fresh every open via the `key` prop
// so its useState initializers re-read props — no setState-in-effect cascade.
function EditLedgerDialog({
  open,
  onOpenChange,
  ledgerId,
  currentName,
  currentColor,
  currentTagline,
  onSave,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  ledgerId: string;
  currentName: string;
  currentColor: string;
  currentTagline: string;
  onSave: (patch: { name?: string; color?: string | null; tagline?: string | null }) => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        {open && (
          <EditLedgerForm
            key={`${ledgerId}|${currentName}|${currentColor}|${currentTagline}`}
            currentName={currentName}
            currentColor={currentColor}
            currentTagline={currentTagline}
            onCancel={() => onOpenChange(false)}
            onSave={onSave}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditLedgerForm({
  currentName,
  currentColor,
  currentTagline,
  onCancel,
  onSave,
}: {
  currentName: string;
  currentColor: string;
  currentTagline: string;
  onCancel: () => void;
  onSave: (patch: { name?: string; color?: string | null; tagline?: string | null }) => void;
}) {
  const tLedger = useTranslations('settings.ledger');
  const tCommon = useTranslations('common');
  const [name, setName] = useState(currentName);
  const [color, setColor] = useState(currentColor);
  const [tagline, setTagline] = useState(currentTagline);

  const trimmedName = name.trim();
  const trimmedTagline = tagline.trim();
  const dirty =
    trimmedName !== currentName.trim() ||
    color !== currentColor ||
    trimmedTagline !== currentTagline.trim();
  const canSave = !!trimmedName && dirty;

  const onSubmit = () => {
    const patch: { name?: string; color?: string | null; tagline?: string | null } = {};
    if (trimmedName !== currentName.trim()) patch.name = trimmedName;
    if (color !== currentColor) patch.color = color;
    if (trimmedTagline !== currentTagline.trim()) patch.tagline = trimmedTagline || null;
    onSave(patch);
  };

  return (
    <>
      <DialogHeader>
        <DialogTitle>{tLedger('editDialog.title')}</DialogTitle>
        <DialogDescription>
          {tLedger('editDialog.description')}
        </DialogDescription>
      </DialogHeader>
      <div className="grid gap-3 py-2">
        <div className="grid gap-1.5">
          <Label htmlFor="edit-ledger-name">{tLedger('editDialog.name')}</Label>
          <Input
            id="edit-ledger-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            maxLength={40}
            autoFocus
          />
        </div>
        <div className="grid gap-1.5">
          <Label htmlFor="edit-ledger-color">{tLedger('editDialog.color')}</Label>
          <div className="flex items-center gap-2">
            <input
              id="edit-ledger-color"
              type="color"
              value={color}
              onChange={(e) => setColor(e.target.value)}
              className="border-border h-9 w-12 cursor-pointer rounded-md border bg-transparent"
            />
            <span className="text-muted-foreground font-mono text-[11px]">{color}</span>
          </div>
        </div>
        <div className="grid gap-1.5">
          <Label htmlFor="edit-ledger-tagline">{tLedger('editDialog.tagline')}</Label>
          <Input
            id="edit-ledger-tagline"
            value={tagline}
            onChange={(e) => setTagline(e.target.value)}
            placeholder={tLedger('editDialog.taglinePlaceholder')}
            maxLength={80}
          />
        </div>
      </div>
      <DialogFooter>
        <Button variant="outline" onClick={onCancel}>{tCommon('cancel')}</Button>
        <Button onClick={onSubmit} disabled={!canSave}>{tCommon('save')}</Button>
      </DialogFooter>
    </>
  );
}

function DeleteLedgerDialog({
  open,
  onOpenChange,
  ledgerName,
  accountCount,
  txnCount,
  onConfirm,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  ledgerName: string;
  accountCount: number;
  txnCount: number;
  onConfirm: () => void;
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        {open && (
          <DeleteLedgerForm
            key={ledgerName}
            ledgerName={ledgerName}
            accountCount={accountCount}
            txnCount={txnCount}
            onCancel={() => onOpenChange(false)}
            onConfirm={onConfirm}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function DeleteLedgerForm({
  ledgerName,
  accountCount,
  txnCount,
  onCancel,
  onConfirm,
}: {
  ledgerName: string;
  accountCount: number;
  txnCount: number;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const tLedger = useTranslations('settings.ledger');
  const tCommon = useTranslations('common');
  const [typed, setTyped] = useState('');
  const matches = typed.trim() === ledgerName;

  return (
    <>
      <DialogHeader>
        <DialogTitle className="text-destructive">{tLedger('deleteDialog.title', { name: ledgerName })}</DialogTitle>
        <DialogDescription>
          {tLedger('deleteDialog.description', { accounts: accountCount, txns: txnCount })}
        </DialogDescription>
      </DialogHeader>
      <div className="grid gap-1.5 py-2">
        <Label htmlFor="delete-ledger-confirm">
          {tLedger('deleteDialog.typeToConfirm', { name: ledgerName })}
        </Label>
        <Input
          id="delete-ledger-confirm"
          value={typed}
          onChange={(e) => setTyped(e.target.value)}
          autoFocus
          placeholder={ledgerName}
          spellCheck={false}
        />
      </div>
      <DialogFooter>
        <Button variant="outline" onClick={onCancel}>{tCommon('cancel')}</Button>
        <Button variant="destructive" onClick={onConfirm} disabled={!matches}>
          {tLedger('deleteDialog.confirmButton')}
        </Button>
      </DialogFooter>
    </>
  );
}
