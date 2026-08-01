import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { newId } from '../_shared/ids';
import { rebuildEntry, type LegInput } from '../../core/entries';
import { resolveCounterpartyIdByName } from '../counterparties/queries';
import { applyRules } from '@/lib/rules/engine';
import {
  createRule as qCreateRule,
  updateRule as qUpdateRule,
  deleteRule as qDeleteRule,
  markRuleApplied,
  rowToRule,
} from './queries';
import type { RulePatchInput } from './types';
import type { Action, Condition, NewRule } from '@/lib/rules/types';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createRule: (exec, args: Args['createRule']) => {
    const ledgerId = str(args.ledgerId || 'personal');
    const condition = args.condition as Condition;
    const actions = (Array.isArray(args.actions) ? args.actions : []) as Action[];
    if (!condition) throw new I18nError('error.required.ruleCondition', {}, 'Rule condition is required');
    const input: NewRule = {
      ledgerId,
      name: args.name == null ? null : str(args.name),
      priority: args.priority != null ? Number(args.priority) : 100,
      condition,
      actions,
      isActive: args.isActive !== false,
      runOnEdit: args.runOnEdit === true,
    };
    const id = args.id ? str(args.id) : newId('rule');
    return qCreateRule(exec, id, input);
  },
  updateRule: (exec, args: Args['updateRule']) => {
    const patch = (args.patch ?? {}) as RulePatchInput;
    return qUpdateRule(exec, str(args.id), patch);
  },
  deleteRule: (exec, args: Args['deleteRule']) =>
    qDeleteRule(exec, str(args.id)),
  backfillRule: async (exec, args: Args['backfillRule']) => {
    const ruleId = str(args.id);
    const ruleRows = await exec('SELECT * FROM rules WHERE id = ?', [ruleId]);
    if (!ruleRows.length) throw new I18nError('error.notFound.rule', {}, 'Rule not found');
    const rule = rowToRule(ruleRows[0]);
    const entryRows = await exec(
      `SELECT e.id, e.ledger_id, e.date, e.time, e.description, e.kind,
              e.notes, e.counterparty_id, e.applied_rule_ids,
              p.account_id, p.amount, p.amount_base, p.currency, p.category_id
         FROM entries e
         JOIN postings p ON p.entry_id = e.id AND p.account_id IS NOT NULL
        WHERE e.ledger_id = ? AND e.status = 'confirmed'
          AND e.kind IN ('income', 'expense', 'refund')`,
      [rule.ledgerId],
    );
    let matched = 0;
    for (const r of entryRows) {
      const tx = {
        id: String(r.id),
        merchant: String(r.description ?? ''),
        category: r.category_id == null ? null : String(r.category_id),
        amount: Number(r.amount_base),
        nativeAmount: Number(r.amount),
        currency: r.currency == null ? undefined : String(r.currency),
        account: String(r.account_id),
        date: String(r.date),
        time: r.time == null ? undefined : String(r.time),
        note: r.notes == null ? undefined : String(r.notes),
        pending: false,
        kind: r.kind == null ? undefined : (String(r.kind) as 'income' | 'expense' | 'transfer' | 'adjustment' | 'refund'),
        ledgerId: String(r.ledger_id),
        counterpartyId: r.counterparty_id == null ? undefined : String(r.counterparty_id),
      };
      const patch = applyRules(tx, [rule]);
      if (!patch.appliedRuleIds.includes(rule.id)) continue;
      matched++;

      const sets: string[] = [];
      const bind: (string | number | null)[] = [];
      if (patch.counterpartyId !== undefined) { sets.push('counterparty_id = ?'); bind.push(patch.counterpartyId); }
      if (patch.merchant !== undefined) {
        sets.push('description = ?');
        bind.push(patch.merchant);
        const cpId = await resolveCounterpartyIdByName(exec, patch.merchant);
        sets.push('counterparty_id = ?');
        bind.push(cpId);
      }
      if (patch.note !== undefined) { sets.push('notes = ?'); bind.push(patch.note); }
      if (patch.kind !== undefined) { sets.push('kind = ?'); bind.push(patch.kind); }
      if (patch.reviewed) { sets.push("reviewed_at = datetime('now')"); }

      const prevRuleIds: string[] = (() => {
        if (r.applied_rule_ids == null) return [];
        try {
          const v = JSON.parse(String(r.applied_rule_ids));
          return Array.isArray(v) ? v.map(String) : [];
        } catch {
          return [];
        }
      })();
      if (!prevRuleIds.includes(rule.id)) prevRuleIds.push(rule.id);
      sets.push('applied_rule_ids = ?');
      bind.push(JSON.stringify(prevRuleIds));

      if (sets.length > 1) {
        sets.push("updated_at = datetime('now')");
        bind.push(tx.id);
        await exec(`UPDATE entries SET ${sets.join(', ')} WHERE id = ?`, bind);
      }

      if (patch.categoryId !== undefined) {
        const [acctLeg] = await exec(
          `SELECT id, account_id, amount, amount_base, exchange_rate, cleared_at, memo
             FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1`,
          [tx.id],
        );
        if (acctLeg) {
          const catLegs = await exec(
            'SELECT category_id FROM postings WHERE entry_id = ? AND category_id IS NOT NULL',
            [tx.id],
          );
          // A purchase paid from several accounts carries exactly one category leg by
          // design, so catLegs.length stays < 2 — but the rebuild below still reads a
          // single account leg (LIMIT 1) and would silently drop every other payment.
          // Skip just this entry's re-categorization (header fields and tags above/
          // below still apply); a batch backfill should skip what it cannot safely do,
          // not abort (mirrored on iOS).
          const [{ n: acctLegCount }] = await exec(
            'SELECT COUNT(*) AS n FROM postings WHERE entry_id = ? AND account_id IS NOT NULL',
            [tx.id],
          );
          if (catLegs.length < 2 && Number(acctLegCount) <= 1) {
            const legs: LegInput[] = [
              {
                id: String(acctLeg.id),
                accountId: String(acctLeg.account_id),
                amount: Number(acctLeg.amount),
                amountBase: Number(acctLeg.amount_base),
                exchangeRate: Number(acctLeg.exchange_rate ?? 1),
                clearedAt: acctLeg.cleared_at == null ? null : String(acctLeg.cleared_at),
                memo: acctLeg.memo == null ? null : String(acctLeg.memo),
              },
            ];
            if (patch.categoryId != null) {
              legs.push({ categoryId: patch.categoryId, amountBase: -Number(acctLeg.amount_base) });
            } else {
              legs.push({ categoryId: null, amountBase: -Number(acctLeg.amount_base) });
            }
            await rebuildEntry(exec, tx.id, { legs });
          }
        }
      }

      if (patch.tagIdsAdd?.length) {
        for (const tagId of patch.tagIdsAdd) {
          await exec(
            'INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)',
            [tx.id, tagId],
          );
        }
      }
    }
    await markRuleApplied(exec, rule.id);
    void matched;
  },
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
