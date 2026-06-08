'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { useTranslations } from 'next-intl';
import { Icon, Money, CatBar } from '@/components/primitives';
import { RefundBadge } from '@/components/refund-badge';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { SearchButton } from '@/components/command-palette';
import { Accordion, AccordionItem, AccordionTrigger, AccordionContent } from '@/components/ui/accordion';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { DropdownMenu, DropdownMenuCheckboxItem, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { useLedger } from '@/components/ledger-provider';
import { useMoney } from '@/components/use-money';
import { useTransactionSheet } from '@/components/transaction-sheet';
import { EmptyState } from '@/components/empty-state';
import { useFinanceStore } from '@/lib/store';
import { MOCK, catById, CURRENCIES } from '@/lib/data';
import { ACCOUNT_TYPE_OPTIONS } from '@/lib/account-types';
import { cn } from '@/lib/utils';
import type { AccountRow } from '@/lib/db/queries/accounts';

const DEFAULT_OPEN_GROUPS = ['cash', 'credit', 'invest'];

type GroupWithAccounts = {
  id: string;
  name: string;
  accounts: { id: string; name: string; color: string }[];
};

// Reserved id for the "ungrouped" bucket — accounts with no group_id.
// Never collides with real group ids (which use the `ag-` prefix or the seed ids).
const UNGROUPED_ID = '__ungrouped__';

// Collapsible account groups, shared by the mobile column and the desktop
// left column. Accounts are created via the header "New" menu; empty groups
// just show a muted placeholder. When `showArchived` is true, archived rows
// in each group are interleaved below the active rows as muted "ghost" rows
// with an Unarchive button.
function AccountGroupAccordion({
  groups,
  balanceOf,
  fmt,
  defaultOpen,
  onEditGroup,
  onDeleteGroup,
  archivedAccounts,
  showArchived,
  onUnarchive,
}: {
  groups: GroupWithAccounts[];
  balanceOf: (id: string) => number;
  fmt: (n: number) => string;
  defaultOpen: string[];
  onEditGroup?: (groupId: string) => void;
  onDeleteGroup?: (groupId: string) => void;
  archivedAccounts: AccountRow[];
  showArchived: boolean;
  onUnarchive: (id: string, name: string) => void;
}) {
  const t = useTranslations('accounts');
  return (
    <Accordion type="multiple" defaultValue={defaultOpen}>
      {groups.map((g) => {
        const groupTotal = g.accounts.reduce((s, a) => s + balanceOf(a.id), 0);
        const empty = g.accounts.length === 0;
        const editable = g.id !== UNGROUPED_ID && onEditGroup && onDeleteGroup;
        // Bucket archived rows by group — accounts with no group land in the
        // synthetic UNGROUPED bucket (groupId = ''), matching the active rows.
        const archivedInGroup = showArchived
          ? archivedAccounts.filter((a) => (a.groupId ?? '') === (g.id === UNGROUPED_ID ? '' : g.id))
          : [];
        const showGhost = archivedInGroup.length > 0;
        return (
          <AccordionItem key={g.id} value={g.id}>
            <AccordionTrigger
              chevronSide="left"
              action={
                editable ? (
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <button
                        type="button"
                        aria-label={t('groupActionsAria', { name: g.name })}
                        className="text-muted-foreground hover:text-foreground ml-2 flex size-7 shrink-0 cursor-pointer items-center justify-center rounded-md"
                      >
                        <Icon name="dots" size={14} />
                      </button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem onSelect={() => onEditGroup!(g.id)}>
                        <Icon name="edit" size={14} />
                        {t('groupActions.rename')}
                      </DropdownMenuItem>
                      <DropdownMenuItem variant="destructive" onSelect={() => onDeleteGroup!(g.id)}>
                        <Icon name="x" size={14} />
                        {t('groupActions.delete')}
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                ) : undefined
              }
            >
              <div className="flex min-w-0 flex-1 items-center gap-2.5">
                <div className="flex-1 font-serif text-lg italic -tracking-[0.2px]">{g.name}</div>
                <span className={cn('font-mono text-[11px] tracking-[0.3px] tabular-nums', empty ? 'text-muted-foreground' : 'text-secondary-foreground')}>
                  {empty ? '—' : `${g.accounts.length} · ${groupTotal < 0 ? '−' : ''}${fmt(Math.abs(groupTotal))}`}
                </span>
              </div>
            </AccordionTrigger>
            <AccordionContent>
              {empty && !showGhost ? (
                <EmptyState variant="card" size="sm" title={t('emptyGroup')} />
              ) : (
                <div className="bg-card border-border rounded-xl border">
                  {g.accounts.map((a, i) => {
                    const bal = balanceOf(a.id);
                    return (
                      <Link key={a.id} href={`/accounts/${a.id}`} className={cn('flex cursor-pointer items-center gap-3 p-3.5 text-inherit no-underline', i && 'border-border border-t-[0.5px]')}>
                        <div className="size-[38px] shrink-0 rounded-lg" style={{ background: a.color }} />
                        <div className="min-w-0 flex-1">
                          <div className="text-sm font-medium">{a.name}</div>
                        </div>
                        <div className="flex items-center gap-2.5">
                          <div className="min-w-[70px] text-right">
                            <div className={cn('font-sans text-base font-medium leading-none tabular-nums', bal < 0 ? 'text-destructive' : 'text-foreground')}>
                              {bal < 0 ? '−' : ''}{fmt(Math.abs(bal))}
                            </div>
                          </div>
                          <Icon name="chev" size={12} className="text-muted-foreground shrink-0" />
                        </div>
                      </Link>
                    );
                  })}
                  {showGhost && archivedInGroup.map((a, i) => (
                    <div
                      key={`archived-${a.id}`}
                      className={cn(
                        'text-muted-foreground flex items-center justify-between gap-3 p-3.5 text-sm italic opacity-60',
                        (i > 0 || g.accounts.length > 0) && 'border-border border-t-[0.5px]',
                      )}
                    >
                      <div className="min-w-0 flex-1">
                        <div className="truncate">{a.name}</div>
                        <div className="text-[11px] not-italic">
                          {t('archived.subtitle', { date: (a.archivedAt ?? '').slice(0, 10) })}
                        </div>
                      </div>
                      <button
                        type="button"
                        className="text-foreground hover:bg-muted shrink-0 rounded-md px-2 py-1 text-xs not-italic"
                        onClick={() => onUnarchive(a.id, a.name)}
                      >
                        {t('unarchive.button')}
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </AccordionContent>
          </AccordionItem>
        );
      })}
    </Accordion>
  );
}

const EMPTY_DRAFT = { name: '', type: 'savings', group: 'cash', currency: '', openingBalance: '', color: '#3a4a5f' };

const CURRENCY_CODES = Object.keys(CURRENCIES);

interface GroupDraft {
  id: string | null; // null => create
  name: string;
}
const EMPTY_GROUP_DRAFT: GroupDraft = { id: null, name: '' };

export default function AccountsPage() {
  const { fmt, toBase } = useMoney();
  const { active, activeId } = useLedger();
  const { openTransaction } = useTransactionSheet();
  const t = useTranslations('accounts');
  const tCommon = useTranslations('common');
  const allTxns = useFinanceStore((s) => s.transactions);
  const accounts = useFinanceStore((s) => s.accounts);
  const accountGroups = useFinanceStore((s) => s.accountGroups);
  const createAccount = useFinanceStore((s) => s.createAccount);
  const createAccountGroup = useFinanceStore((s) => s.createAccountGroup);
  const updateAccountGroup = useFinanceStore((s) => s.updateAccountGroup);
  const deleteAccountGroup = useFinanceStore((s) => s.deleteAccountGroup);
  // Recent activity shows confirmed transactions only; unconfirmed (pending)
  // items live in the per-account "To confirm" section and the Pending screen.
  const ledgerTxns = allTxns.filter((t) => (t.ledgerId ?? 'personal') === activeId && !t.pending);

  const [createOpen, setCreateOpen] = useState(false);
  const [draft, setDraft] = useState(EMPTY_DRAFT);
  const [groupDialogOpen, setGroupDialogOpen] = useState(false);
  const [groupDraft, setGroupDraft] = useState<GroupDraft>(EMPTY_GROUP_DRAFT);
  const [confirmDeleteGroupId, setConfirmDeleteGroupId] = useState<string | null>(null);
  const [showArchived, setShowArchived] = useState(false);
  const [archivedAccounts, setArchivedAccounts] = useState<AccountRow[]>([]);
  const [archivedLoaded, setArchivedLoaded] = useState(false);

  // Load the archived set on demand the first time the user toggles the filter
  // on. Subsequent toggles reuse the cached slice (re-fetches only happen when
  // the user re-enables the filter after a page reload). When the user
  // archives from a per-account edit dialog we don't auto-insert the new row
  // here — toggling the filter off and on re-fetches and picks it up.
  useEffect(() => {
    if (!showArchived || archivedLoaded) return;
    let cancelled = false;
    (async () => {
      const res = await fetch(`/api/accounts/archived?ledgerId=${encodeURIComponent(activeId)}`);
      if (!res.ok) throw new Error(`listArchivedAccounts HTTP ${res.status}`);
      const rows = (await res.json()) as AccountRow[];
      if (!cancelled) {
        setArchivedAccounts(rows);
        setArchivedLoaded(true);
      }
    })().catch((err) => console.error('listArchivedAccounts failed', err));
    return () => {
      cancelled = true;
    };
  }, [showArchived, archivedLoaded, activeId]);

  const openCreate = (groupId?: string) => {
    setDraft({ ...EMPTY_DRAFT, group: groupId ?? 'cash', currency: active.base });
    setCreateOpen(true);
  };

  const saveCreate = () => {
    const name = draft.name.trim();
    if (!name) return;
    createAccount({
      name,
      type: draft.type,
      currency: draft.currency || active.base,
      groupId: draft.group,
      openingBalance: Number(draft.openingBalance) || 0,
      color: draft.color,
      ledgerId: activeId,
    });
    toast.success(t('createDialog.createdToast'), { description: name });
    setCreateOpen(false);
  };

  // Accounts (name/color/group) and balances now come from the projected
  // DB rows; the static mock is only a pre-hydration fallback so first paint
  // isn't empty.
  const ledgerAccountRows = accounts.filter((a) => a.ledgerId === activeId);
  // Balances are stored in each account's own currency; re-express them in the
  // ledger base so group subtotals and net worth (which sum across accounts) and
  // the base→display `fmt` are all valid. A no-op when account currency == base.
  const balanceOf = (id: string) => {
    const a = ledgerAccountRows.find((r) => r.id === id);
    return a ? toBase(a.balance, a.currency) : 0;
  };

  const ledgerAccounts = ledgerAccountRows.length
    ? ledgerAccountRows.map((a) => ({ id: a.id, name: a.name, color: a.color ?? '#6b7280', group: a.groupId ?? '' }))
    : MOCK.accounts
        .filter((a) => ((a as { ledger?: string }).ledger ?? 'personal') === activeId)
        .map((a) => ({ id: a.id, name: a.name, color: a.color, group: a.group }));

  const ledgerGroups = accountGroups.filter((g) => g.ledgerId === activeId);
  // Pre-hydration fallback so first paint still has the seed groups.
  const groupShells: { id: string; name: string }[] = ledgerGroups.length
    ? ledgerGroups.map((g) => ({ id: g.id, name: g.name }))
    : MOCK.accountGroups.map((g) => ({ id: g.id, name: g.name }));

  const openCreateGroup = () => {
    setGroupDraft(EMPTY_GROUP_DRAFT);
    setGroupDialogOpen(true);
  };

  const openEditGroup = (id: string) => {
    const g = ledgerGroups.find((x) => x.id === id);
    if (!g) return;
    setGroupDraft({ id: g.id, name: g.name });
    setGroupDialogOpen(true);
  };

  const saveGroup = () => {
    const name = groupDraft.name.trim();
    if (!name) return;
    if (groupDraft.id) {
      updateAccountGroup(groupDraft.id, { name });
      toast.success(t('groupDialog.updatedToast'));
    } else {
      createAccountGroup({ name, ledgerId: activeId });
      toast.success(t('groupDialog.createdToast'), { description: name });
    }
    setGroupDialogOpen(false);
  };

  const confirmDelete = () => {
    if (!confirmDeleteGroupId) return;
    deleteAccountGroup(confirmDeleteGroupId);
    toast.success(t('deleteGroupDialog.deletedToast'));
    setConfirmDeleteGroupId(null);
  };

  // Optimistic local-state remove — the ghost row vanishes immediately. The
  // store action fires syncMutation('unarchiveAccount', …); the server's
  // projected state comes back and the row reappears in the active list.
  const handleUnarchive = (id: string, name: string) => {
    setArchivedAccounts((prev) => prev.filter((a) => a.id !== id));
    useFinanceStore.getState().unarchiveAccount(id);
    toast.success(t('unarchive.toast'), { description: name });
  };

  const trailing = (
    <div className="flex items-center gap-1">
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label={t('filter.aria')}
            className="border-border text-foreground flex size-9 cursor-pointer items-center justify-center rounded-full border"
          >
            <Icon name="filter" size={16} />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuCheckboxItem
            checked={showArchived}
            onCheckedChange={(v) => setShowArchived(!!v)}
          >
            {t('filter.includeArchived')}
          </DropdownMenuCheckboxItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <SearchButton />
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label={t('addAria')}
            className="border-border text-foreground flex size-9 cursor-pointer items-center justify-center rounded-full border"
          >
            <Icon name="plus" size={16} />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onSelect={() => openCreate()}>
            <Icon name="wallet" size={14} />
            {t('menu.newAccount')}
          </DropdownMenuItem>
          <DropdownMenuItem onSelect={() => openCreateGroup()}>
            <Icon name="tags" size={14} />
            {t('menu.newGroup')}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
  );

  const createDialog = (
    <Dialog open={createOpen} onOpenChange={setCreateOpen}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('createDialog.title')}</DialogTitle>
          <DialogDescription>{t('createDialog.description', { ledger: active.name })}</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="new-name">{t('createDialog.name')}</Label>
            <Input id="new-name" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} autoFocus />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="new-type">{t('createDialog.type')}</Label>
              <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v })}>
                <SelectTrigger id="new-type" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {ACCOUNT_TYPE_OPTIONS.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="new-group">{t('createDialog.group')}</Label>
              <Select value={draft.group} onValueChange={(v) => setDraft({ ...draft, group: v })}>
                <SelectTrigger id="new-group" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {groupShells.map((g) => <SelectItem key={g.id} value={g.id}>{g.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="new-currency">{t('createDialog.currency')}</Label>
              <Select value={draft.currency} onValueChange={(v) => setDraft({ ...draft, currency: v })}>
                <SelectTrigger id="new-currency" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {CURRENCY_CODES.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="new-balance">{t('createDialog.openingBalance', { currency: draft.currency || active.base })}</Label>
              <Input id="new-balance" inputMode="decimal" value={draft.openingBalance} onChange={(e) => setDraft({ ...draft, openingBalance: e.target.value })} placeholder={t('createDialog.openingBalancePlaceholder')} />
            </div>
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="new-color">{t('createDialog.cardColor')}</Label>
            <input id="new-color" type="color" value={draft.color} onChange={(e) => setDraft({ ...draft, color: e.target.value })} className="border-border h-9 w-full cursor-pointer rounded-md border bg-transparent" />
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">{tCommon('cancel')}</Button>
          </DialogClose>
          <Button onClick={saveCreate} disabled={!draft.name.trim()}>{tCommon('create')}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  if (ledgerAccounts.length === 0) {
    return (
      <MobilePage>
        <ScreenHeader title={t('title')} trailing={trailing} />
        <EmptyState
          variant="page"
          icon="wallet"
          title={t.rich('empty.title', {
            ledger: () => <span className="text-foreground font-medium">{active.name}</span>,
          })}
          description={t('empty.description')}
        />
        {createDialog}

        <Dialog open={groupDialogOpen} onOpenChange={setGroupDialogOpen}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>{groupDraft.id ? t('groupDialog.editTitle') : t('groupDialog.newTitle')}</DialogTitle>
              <DialogDescription>
                {groupDraft.id ? t('groupDialog.editDescription') : t('groupDialog.newDescription', { ledger: active.name })}
              </DialogDescription>
            </DialogHeader>
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="group-name-empty">{t('groupDialog.name')}</Label>
                <Input
                  id="group-name-empty"
                  value={groupDraft.name}
                  onChange={(e) => setGroupDraft({ ...groupDraft, name: e.target.value })}
                  autoFocus
                />
              </div>
            </div>
            <DialogFooter>
              <DialogClose asChild>
                <Button variant="outline">{tCommon('cancel')}</Button>
              </DialogClose>
              <Button onClick={saveGroup} disabled={!groupDraft.name.trim()}>
                {groupDraft.id ? tCommon('save') : tCommon('create')}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </MobilePage>
    );
  }

  const ungroupedAccts = ledgerAccounts.filter((a) => !a.group || !groupShells.some((g) => g.id === a.group));
  const groupedAccounts = [
    ...groupShells.map((g) => ({ id: g.id, name: g.name, accounts: ledgerAccounts.filter((a) => a.group === g.id) })),
    ...(ungroupedAccts.length ? [{ id: UNGROUPED_ID, name: t('ungroupedLabel'), accounts: ungroupedAccts }] : []),
  ];

  const deleteTarget = confirmDeleteGroupId ? ledgerGroups.find((g) => g.id === confirmDeleteGroupId) : null;
  const deleteTargetAcctCount = deleteTarget ? ledgerAccounts.filter((a) => a.group === deleteTarget.id).length : 0;

  return (
    <MobilePage>
      <ScreenHeader title={t('title')} trailing={trailing} />

      <div className="px-5 pb-[120px] md:hidden">
        <AccountGroupAccordion
          groups={groupedAccounts}
          balanceOf={balanceOf}
          fmt={fmt}
          defaultOpen={DEFAULT_OPEN_GROUPS}
          onEditGroup={openEditGroup}
          onDeleteGroup={setConfirmDeleteGroupId}
          archivedAccounts={archivedAccounts}
          showArchived={showArchived}
          onUnarchive={handleUnarchive}
        />
      </div>

      <div className="hidden px-8 pb-12 md:block">
        <div className="grid grid-cols-1 items-start gap-8 md:grid-cols-[1.7fr_1fr]">
          <div className="min-w-0">
            <div className="mb-3 flex items-center justify-between">
              <div className="font-serif text-lg italic">{t('allAccounts')}</div>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button size="sm" variant="outline">
                    <Icon name="plus" size={14} />
                    {t('newButton')}
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem onSelect={() => openCreate()}>
                    <Icon name="wallet" size={14} />
                    {t('menu.newAccount')}
                  </DropdownMenuItem>
                  <DropdownMenuItem onSelect={() => openCreateGroup()}>
                    <Icon name="tags" size={14} />
                    {t('menu.newGroup')}
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
            <AccountGroupAccordion
              groups={groupedAccounts}
              balanceOf={balanceOf}
              fmt={fmt}
              defaultOpen={DEFAULT_OPEN_GROUPS}
              onEditGroup={openEditGroup}
              onDeleteGroup={setConfirmDeleteGroupId}
              archivedAccounts={archivedAccounts}
              showArchived={showArchived}
              onUnarchive={handleUnarchive}
            />
          </div>

          <aside className="min-w-0">
            <div className="mb-3 font-serif text-lg italic">{t('recentActivity')}</div>
            <div className="bg-card border-border overflow-hidden rounded-xl border">
              {[...ledgerTxns]
                .sort((a, b) => b.date.localeCompare(a.date))
                .slice(0, 8)
                .map((t, i) => {
                  const cat = catById(t.category);
                  const inc = t.amount > 0;
                  return (
                    <button
                      key={t.id}
                      type="button"
                      onClick={() => openTransaction(t.id)}
                      className={cn('hover:bg-secondary/40 flex w-full items-center gap-3 px-4 py-3 text-left text-inherit', i && 'border-border border-t-[0.5px]')}
                    >
                      <CatBar color={cat.color} />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-1.5">
                          <span className="truncate text-sm font-medium">{t.merchant}</span>
                          {t.kind === 'refund' && <RefundBadge />}
                        </div>
                        <div className="text-muted-foreground text-xs">{t.date.replace(/-/g, '/')}{t.time ? ' ' + t.time.slice(0, 5) : ''} · {cat.name}</div>
                      </div>
                      <Money value={t.amount} signed={inc} className={cn('shrink-0 font-mono text-[13px] font-semibold', inc ? 'text-success' : 'text-foreground')} />
                    </button>
                  );
                })}
            </div>
          </aside>
        </div>
      </div>
      {createDialog}

      <Dialog open={groupDialogOpen} onOpenChange={setGroupDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{groupDraft.id ? t('groupDialog.editTitle') : t('groupDialog.newTitle')}</DialogTitle>
            <DialogDescription>
              {groupDraft.id ? t('groupDialog.editDescription') : t('groupDialog.newDescription', { ledger: active.name })}
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="group-name">{t('groupDialog.name')}</Label>
              <Input
                id="group-name"
                value={groupDraft.name}
                onChange={(e) => setGroupDraft({ ...groupDraft, name: e.target.value })}
                autoFocus
              />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button onClick={saveGroup} disabled={!groupDraft.name.trim()}>
              {groupDraft.id ? tCommon('save') : tCommon('create')}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!confirmDeleteGroupId} onOpenChange={(o) => !o && setConfirmDeleteGroupId(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t('deleteGroupDialog.title')}</DialogTitle>
            <DialogDescription>
              {deleteTarget?.name}
              {deleteTargetAcctCount > 0 && (
                <> · {t('deleteGroupDialog.moveHint', { count: deleteTargetAcctCount })}</>
              )}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">{tCommon('cancel')}</Button>
            </DialogClose>
            <Button variant="destructive" onClick={confirmDelete}>{tCommon('delete')}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
