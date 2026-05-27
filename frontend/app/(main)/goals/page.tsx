'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Ring, Money, Icon } from '@/components/primitives';
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
import { RowActions } from '@/components/RowActions';
import { useFinanceStore } from '@/lib/store';

export default function GoalsPage() {
  const { active, activeId } = useLedger();
  const allGoals = useFinanceStore((s) => s.goals);
  const createGoal = useFinanceStore((s) => s.createGoal);
  const contributeGoal = useFinanceStore((s) => s.contributeGoal);
  const updateGoal = useFinanceStore((s) => s.updateGoal);
  const deleteGoal = useFinanceStore((s) => s.deleteGoal);

  const goals = allGoals.filter((g) => g.ledgerId === activeId);
  const saved = goals.reduce((s, g) => s + g.saved, 0);
  const target = goals.reduce((s, g) => s + g.target, 0);
  const pct = target ? Math.round((saved / target) * 100) : 0;

  const [name, setName] = useState('');
  const [targetInput, setTargetInput] = useState('');
  const [eta, setEta] = useState('');
  const [contributing, setContributing] = useState<{ id: string; name: string } | null>(null);
  const [contribInput, setContribInput] = useState('');
  const [editing, setEditing] = useState<{ id: string; name: string; target: string; eta: string } | null>(null);

  const submitCreate = () => {
    const n = name.trim();
    const t = parseFloat(targetInput);
    if (!n) return void toast.error('Enter a goal name');
    if (!(t > 0)) return void toast.error('Enter a target greater than 0');
    createGoal({ name: n, target: t, eta: eta.trim() || undefined, ledgerId: activeId });
    toast.success('Goal created', { description: n });
    setName('');
    setTargetInput('');
    setEta('');
  };

  const submitEdit = () => {
    if (!editing) return;
    const n = editing.name.trim();
    const t = parseFloat(editing.target);
    if (!n) return void toast.error('Enter a goal name');
    if (!(t > 0)) return void toast.error('Enter a target greater than 0');
    updateGoal(editing.id, { name: n, target: t, eta: editing.eta.trim() || null });
    toast.success('Goal updated', { description: n });
    setEditing(null);
  };

  const submitContribution = () => {
    const amt = parseFloat(contribInput);
    if (!contributing || !(amt > 0)) return void toast.error('Enter an amount greater than 0');
    contributeGoal(contributing.id, amt);
    toast.success('Contribution added', { description: `${contributing.name} · +${amt.toLocaleString()}` });
    setContributing(null);
    setContribInput('');
  };

  const createDialog = (
    <Dialog>
      <DialogTrigger asChild>
        <IconButton icon="plus" aria-label="New goal" />
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New goal</DialogTitle>
          <DialogDescription>Set a savings target in {active.name}.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label>Name</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. New car" autoFocus />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Target</Label>
            <Input
              type="number"
              inputMode="decimal"
              value={targetInput}
              onChange={(e) => setTargetInput(e.target.value)}
              placeholder="0.00"
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label>Target date (optional)</Label>
            <Input value={eta} onChange={(e) => setEta(e.target.value)} placeholder="e.g. Dec 2026" />
          </div>
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <DialogClose asChild>
            <Button onClick={submitCreate}>Create</Button>
          </DialogClose>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  return (
    <MobilePage header={<ScreenHeader title="Goals" trailing={createDialog} />}>
      <div className="px-5 pb-[22px]">
        <PageHeader
          label="Saved toward goals"
          value={<Money value={saved} mono={false} />}
          sublabel={
            <>
              of <Money value={target} /> · {pct}%
            </>
          }
        />
        <div className="bg-secondary mt-1 h-2 overflow-hidden rounded-full">
          <div className="bg-primary h-full" style={{ width: `${pct}%` }} />
        </div>
      </div>

      <div className="flex flex-col gap-2.5 px-5 pb-[120px]">
        {goals.length === 0 && (
          <div className="text-muted-foreground rounded-xl border border-dashed py-10 text-center text-sm">
            No goals in {active.name} yet — use the + button to add one.
          </div>
        )}
        {goals.map((g) => {
          const p = g.target ? Math.round((g.saved / g.target) * 100) : 0;
          return (
            <div key={g.id} className="bg-card border-border flex items-center gap-4 rounded-xl border p-4">
              <Ring
                value={g.saved}
                max={g.target}
                size={60}
                stroke={6}
                color={`oklch(0.65 0.15 ${g.hue})`}
                track="var(--secondary)"
              >
                <span className="font-serif text-sm">{p}%</span>
              </Ring>
              <div className="min-w-0 flex-1">
                <div className="text-[15px] font-medium">{g.name}</div>
                {g.eta && <div className="text-muted-foreground mt-0.5 text-xs">ETA {g.eta}</div>}
                <div className="mt-1 text-sm">
                  <Money value={g.saved} className="font-medium" />
                  <span className="text-muted-foreground"> / </span>
                  <Money value={g.target} className="text-muted-foreground" />
                </div>
              </div>
              <Button
                variant="outline"
                size="sm"
                className="h-8 shrink-0"
                onClick={() => {
                  setContribInput('');
                  setContributing({ id: g.id, name: g.name });
                }}
              >
                <Icon name="plus" size={12} />
                Add
              </Button>
              <RowActions
                onEdit={() => setEditing({ id: g.id, name: g.name, target: String(g.target), eta: g.eta ?? '' })}
                onDelete={() => { deleteGoal(g.id); toast.success('Goal deleted', { description: g.name }); }}
                confirmTitle={`Delete ${g.name}?`}
                confirmDescription="This removes the savings goal. Your account balances are unaffected."
              />
            </div>
          );
        })}
      </div>

      <Dialog open={!!contributing} onOpenChange={(o) => !o && setContributing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add to {contributing?.name}</DialogTitle>
            <DialogDescription>Record a contribution toward this goal.</DialogDescription>
          </DialogHeader>
          <Input
            type="number"
            inputMode="decimal"
            value={contribInput}
            onChange={(e) => setContribInput(e.target.value)}
            placeholder="0.00"
            autoFocus
            onKeyDown={(e) => e.key === 'Enter' && submitContribution()}
          />
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitContribution}>Add</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit goal</DialogTitle>
            <DialogDescription>Update the name, target or date.</DialogDescription>
          </DialogHeader>
          {editing && (
            <div className="flex flex-col gap-3">
              <div className="flex flex-col gap-1.5">
                <Label>Name</Label>
                <Input value={editing.name} onChange={(e) => setEditing((p) => (p ? { ...p, name: e.target.value } : p))} autoFocus />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Target</Label>
                <Input type="number" inputMode="decimal" value={editing.target} onChange={(e) => setEditing((p) => (p ? { ...p, target: e.target.value } : p))} />
              </div>
              <div className="flex flex-col gap-1.5">
                <Label>Target date (optional)</Label>
                <Input value={editing.eta} onChange={(e) => setEditing((p) => (p ? { ...p, eta: e.target.value } : p))} placeholder="e.g. Dec 2026" />
              </div>
            </div>
          )}
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline">Cancel</Button>
            </DialogClose>
            <Button onClick={submitEdit}>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </MobilePage>
  );
}
