'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Money, MerchantGlyph } from '@/components/primitives';
import { ScreenHeader, MobilePage, IconButton, PageHeader } from '@/components/MobileComponents';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { useLedger } from '@/components/ledger-provider';
import { useFinanceStore } from '@/lib/store';

export default function SubscriptionsPage() {
  const { active, activeId } = useLedger();
  const allSubs = useFinanceStore((s) => s.subscriptions);
  const createSubscription = useFinanceStore((s) => s.createSubscription);

  const subs = allSubs.filter((s) => s.ledgerId === activeId);
  const monthly = subs.reduce((s, x) => s + x.amount, 0);

  const [name, setName] = useState('');
  const [amount, setAmount] = useState('');
  const [next, setNext] = useState('');

  const submit = () => {
    const n = name.trim();
    const a = parseFloat(amount);
    if (!n) return void toast.error('Enter a name');
    if (!(a > 0)) return void toast.error('Enter an amount greater than 0');
    createSubscription({ name: n, amount: a, next: next.trim() || undefined, ledgerId: activeId });
    toast.success('Subscription added', { description: n });
    setName('');
    setAmount('');
    setNext('');
  };

  const addDialog = (
    <Dialog>
      <DialogTrigger asChild>
        <IconButton icon="plus" aria-label="Add subscription" />
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New subscription</DialogTitle>
          <DialogDescription>Track a recurring subscription in {active.name}.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label>Name</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Disney+" autoFocus />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Amount / month</Label>
            <Input type="number" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Next charge (optional)</Label>
            <Input value={next} onChange={(e) => setNext(e.target.value)} placeholder="e.g. Jun 30" />
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <DialogClose asChild>
            <Button onClick={submit}>Add</Button>
          </DialogClose>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  return (
    <MobilePage header={<ScreenHeader title="Subscriptions" trailing={addDialog} />}>
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Monthly subscriptions"
          value={<Money value={monthly} mono={false} />}
          sublabel={
            <>
              <Money value={monthly * 12} /> per year · {subs.length} active
            </>
          }
        />
      </div>

      <div className="flex flex-col gap-2.5 px-5 pb-[120px]">
        {subs.length === 0 && (
          <div className="text-muted-foreground rounded-xl border border-dashed py-10 text-center text-sm">
            No subscriptions in {active.name} yet — use the + button to add one.
          </div>
        )}
        {subs.map((s) => (
          <div key={s.id} className="bg-card border-border flex items-center gap-3.5 rounded-xl border p-3.5">
            <MerchantGlyph name={s.name} hue={s.hue} size={40} />
            <div className="min-w-0 flex-1">
              <div className="text-sm font-medium">{s.name}</div>
              <div className="text-muted-foreground mt-0.5 text-xs capitalize">
                {s.cadence}
                {s.next ? ` · next ${s.next}` : ''}
              </div>
            </div>
            <div className="text-right">
              <Money value={s.amount} className="text-sm font-medium" />
              <div className="text-muted-foreground text-[11px]">
                <Money value={s.amount * 12} />
                /yr
              </div>
            </div>
          </div>
        ))}
      </div>
    </MobilePage>
  );
}
