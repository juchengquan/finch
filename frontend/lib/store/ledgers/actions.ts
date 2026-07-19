// frontend/lib/store/ledgers/actions.ts — ledger action creators.
// Extracted from lib/store.ts:391-468 (createLedger, updateLedger,
// setDefaultLedger, deleteLedger).
//
// `changeLedgerBase` lives in `_app/actions.ts` — it's the one ledger
// action that crosses into the cross-cutting `appActions` because it
// has the same surface as the prefs actions (mutation + re-projection).

import { newId } from '../_shared/ids';
import { syncMutation } from '../hydrate';
import type { SetState, GetState } from '../_shared/types';

export const ledgerActions = (set: SetState, get: GetState) => ({
  createLedger: (input: { name: string; base: string; color?: string | null; tagline?: string | null }): string => {
    // App-side id like every other createX. Server validates non-collision.
    const id = newId('ledger');
    const base = input.base.toUpperCase();
    // Optimistic: project the new row with zero counts.
    set((s) => ({
      ledgers: [
        ...s.ledgers,
        {
          id,
          name: input.name,
          base,
          isDefault: 0,
          color: input.color ?? null,
          tagline: input.tagline ?? null,
          accounts: 0,
          txns: 0,
        },
      ],
    }));
    syncMutation('createLedger', {
      id,
      name: input.name,
      base,
      color: input.color ?? null,
      tagline: input.tagline ?? null,
    });
    return id;
  },

  updateLedger: (id: string, patch: { name?: string; color?: string | null; tagline?: string | null }): void => {
    set((s) => ({
      ledgers: s.ledgers.map((l) => (l.id === id ? { ...l, ...patch } : l)),
    }));
    syncMutation('updateLedger', { id, patch });
  },

  setDefaultLedger: (id: string): void => {
    set((s) => ({
      ledgers: s.ledgers.map((l) => ({ ...l, isDefault: l.id === id ? 1 : 0 })),
    }));
    syncMutation('setDefaultLedger', { id });
  },

  deleteLedger: (id: string): void => {
    // Optimistic: drop the row + every projected slice scoped to this ledger.
    // The server re-projection arrives with the cleaned-up state shortly.
    set((s) => {
      const remaining = s.ledgers.filter((l) => l.id !== id);
      const wasDefault = s.ledgers.find((l) => l.id === id)?.isDefault === 1;
      // Default reassignment: promote first by name when the deleted was default.
      const promoteId = wasDefault
        ? [...remaining].sort((a, b) => a.name.localeCompare(b.name))[0]?.id ?? null
        : null;
      const ledgers = promoteId
        ? remaining.map((l) => ({ ...l, isDefault: l.id === promoteId ? 1 : 0 }))
        : remaining;
      return {
        ledgers,
        accounts: s.accounts.filter((a) => a.ledgerId !== id),
        transactions: s.transactions.filter((t) => (t.ledgerId ?? 'personal') !== id),
        categories: s.categories.filter((c) => c.ledgerId !== id),
        tags: s.tags.filter((t) => t.ledgerId !== id),
        // Merchants are global — they survive a ledger deletion.
        budgets: s.budgets.filter((b) => b.ledgerId !== id),
        budgetGroups: s.budgetGroups.filter((g) => g.ledgerId !== id),
        accountGroups: s.accountGroups.filter((g) => g.ledgerId !== id),
        scheduled: s.scheduled, // no ledger_id on the projected shape; server filters
        holdings: s.holdings.filter((h) => h.ledgerId !== id),
        rules: s.rules.filter((r) => r.ledgerId !== id),
        attachments: s.attachments.filter((a) => a.ledgerId !== id),
        displayCurrencyByLedger: Object.fromEntries(
          Object.entries(s.displayCurrencyByLedger).filter(([k]) => k !== id),
        ),
      };
    });
    syncMutation('deleteLedger', { id });
  },
});
