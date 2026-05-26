'use client';

import { useParams, useRouter } from 'next/navigation';
import { toast } from 'sonner';
import { Icon, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader } from '@/components/MobileComponents';
import { useMoney } from '@/components/use-money';
import { catById, acctById, MOCK } from '@/lib/data';
import { useFinanceStore } from '@/lib/store';
import { cn } from '@/lib/utils';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

export default function TxDetailPage() {
  const { fmt } = useMoney();
  const params = useParams();
  const router = useRouter();
  const txId = params.id as string;

  const tx = useFinanceStore((s) => s.transactions.find((t) => t.id === txId));
  const updateTransaction = useFinanceStore((s) => s.updateTransaction);
  const deleteTransaction = useFinanceStore((s) => s.deleteTransaction);

  if (!tx) {
    return (
      <div className="px-5 pb-[120px]">
        <ScreenHeader title="" back />
        <div className="text-muted-foreground py-20 text-center text-sm">Transaction not found</div>
      </div>
    );
  }

  const cat = catById(tx.category);
  const acct = acctById(tx.account);
  const when = new Date(`${tx.date}T${tx.time ?? '00:00'}`);
  const whenStr = `${when.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })} · ${when.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}`;
  const acctLabel = acct.last4 ? `${acct.name} · ${acct.last4}` : acct.name;

  const toggleRecurring = () => {
    updateTransaction(tx.id, { recurring: !tx.recurring });
    toast.success(tx.recurring ? 'Removed recurring' : 'Marked as recurring');
  };

  const remove = () => {
    deleteTransaction(tx.id);
    toast.success('Transaction deleted');
    router.back();
  };

  return (
    <div className="px-5 pb-[120px]">
      <ScreenHeader
        title=""
        back
        trailing={
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                aria-label="More actions"
                className="border-border text-foreground flex size-9 cursor-pointer items-center justify-center rounded-full border"
              >
                <Icon name="dots" size={16} />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={toggleRecurring}>
                <Icon name="sync" size={14} />
                {tx.recurring ? 'Remove recurring' : 'Mark as recurring'}
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem variant="destructive" onClick={remove}>
                <Icon name="x" size={14} />
                Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        }
      />

      <div className="px-6 pb-7 text-center">
        <MerchantGlyph name={tx.merchant} size={64} hue={cat.hue} />
        <div className="text-muted-foreground mt-[18px] font-serif text-[22px] italic">
          {tx.amount > 0 ? 'You received from' : 'You spent at'}
        </div>
        <div className="mt-1 font-serif text-[34px] leading-none -tracking-[0.8px]">{tx.merchant}</div>
        <div className="mt-[18px] font-serif text-[56px] font-normal -tracking-[2px]">
          {fmt(Math.abs(tx.amount))}
        </div>
        <div className="text-muted-foreground mt-1.5 text-xs">
          {whenStr} · {acct.name}
        </div>
      </div>

      <div className="flex gap-2 pb-[22px]">
        <button
          type="button"
          onClick={() => toast('Split — coming soon')}
          className="border-border text-foreground flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border"
        >
          <Icon name="split" size={18} />
          <span className="text-[10px] font-medium">Split</span>
        </button>
        <button
          type="button"
          onClick={toggleRecurring}
          className={cn(
            'flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border',
            tx.recurring ? 'border-primary text-primary' : 'border-border text-foreground',
          )}
        >
          <Icon name="sync" size={18} />
          <span className="text-[10px] font-medium">Recurring</span>
        </button>
        <button
          type="button"
          onClick={() => toast('Receipt — coming soon')}
          className="border-border text-foreground flex h-[60px] flex-1 cursor-pointer flex-col items-center justify-center gap-1 rounded-xl border"
        >
          <Icon name="cam" size={18} />
          <span className="text-[10px] font-medium">Receipt</span>
        </button>
      </div>

      <div className="bg-card border-border rounded-[14px] border px-4 py-1">
        <div className="border-border flex items-center justify-between py-2 text-[13px]">
          <span className="text-muted-foreground">Category</span>
          <Select
            value={tx.category ?? 'uncategorized'}
            onValueChange={(v) => {
              updateTransaction(tx.id, { category: v === 'uncategorized' ? null : v });
              toast.success('Category updated');
            }}
          >
            <SelectTrigger size="sm" className="h-7 border-0 shadow-none">
              <SelectValue placeholder="Uncategorized" />
            </SelectTrigger>
            <SelectContent align="end">
              {MOCK.categories.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        {[
          { l: 'Account', v: acctLabel },
          { l: 'Status', v: tx.pending ? 'Pending' : 'Posted' },
          { l: 'Note', v: tx.note || '—' },
          { l: 'Recurring', v: tx.recurring ? 'Yes' : 'No' },
        ].map((r) => (
          <div key={r.l} className="border-border flex items-center justify-between border-t-[0.5px] py-3 text-[13px]">
            <span className="text-muted-foreground">{r.l}</span>
            <span>{r.v}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
