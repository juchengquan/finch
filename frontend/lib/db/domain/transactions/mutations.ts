import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { withDedupMessage } from '../_shared/with-dedup-message';
import { txTouches, mergeTouches } from '../_shared/tx-touches';
import { unlinkAttachmentFiles } from '../_shared/attachment-cleanup';
import { invalidateRollover } from '@/lib/budgets/rollover';
import {
  addTransaction as qAddTransaction,
  updateTransaction as qUpdateTransaction,
  deleteTransactionRow as qDeleteTransactionRow,
  confirmTransaction as qConfirmTransaction,
  confirmPendingWithMerchant as qConfirmPendingWithMerchant,
  type AddInput,
} from './queries';
import {
  getAttachmentFile,
  getAttachmentRelPathsForTransaction,
  deleteAttachment,
} from '../attachments/queries';
import {
  postAdjustment,
  rebuildEntry,
  resolveEntryRef,
  recomputeAccountFromPostings,
  type LegInput,
} from '../../core/entries';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);
const r2 = (n: number) => Math.round(n * 100) / 100;

export const handlers = {
  addTransaction: async (exec, args: Args['addTransaction']) => {
    const id = await withDedupMessage(() => qAddTransaction(exec, args as unknown as AddInput));
    const touches = await txTouches(exec, id);
    if (touches) {
      await invalidateRollover(
        exec,
        { categoryIds: touches.categoryIds, accountIds: [touches.accountId] },
        touches.date,
      );
    }
    return;
  },
  adjustAccountBalance: async (exec, args: Args['adjustAccountBalance']) => {
    const accountId = str(args.accountId);
    const target = Number(args.targetBalance);
    if (!Number.isFinite(target)) throw new I18nError('error.adjust.targetRequired', {}, 'Enter a target balance');
    const [acct] = await exec('SELECT ledger_id, current_balance FROM accounts WHERE id = ?', [accountId]);
    if (!acct) throw new I18nError('error.notFound.account', {}, 'Account not found');
    const delta = r2(target - Number(acct.current_balance));
    const source = args.source === 'reconcile' ? 'reconcile' : 'manual';
    await postAdjustment(exec, {
      ledgerId: String(acct.ledger_id),
      accountId,
      delta,
      date: args.date ? str(args.date) : new Date().toISOString().slice(0, 10),
      note: args.note ? str(args.note) : undefined,
      source,
    });
    return;
  },
  updateTransaction: async (exec, args: Args['updateTransaction']) => {
    const id = str(args.id);
    const before = await txTouches(exec, id);
    const { oldAccountId } = await qUpdateTransaction(exec, id, args.patch as Parameters<typeof qUpdateTransaction>[2]);
    if (oldAccountId) {
      await recomputeAccountFromPostings(exec, oldAccountId);
    }
    const after = await txTouches(exec, id);
    const merged = mergeTouches(before, after);
    if (merged) {
      await invalidateRollover(
        exec,
        { categoryIds: merged.categoryIds, accountIds: merged.accountIds },
        merged.earliestDate,
      );
    }
    return;
  },
  setCleared: async (exec, args: Args['setCleared']) => {
    const id = str(args.id);
    const cleared = args.cleared === true;
    const ref = await resolveEntryRef(exec, id);
    const postingId = ref?.postingId ?? id;
    await exec(
      cleared
        ? "UPDATE postings SET cleared_at = datetime('now') WHERE id = ?"
        : 'UPDATE postings SET cleared_at = NULL WHERE id = ?',
      [postingId],
    );
    return;
  },
  setReviewed: async (exec, args: Args['setReviewed']) => {
    const id = str(args.id);
    const reviewed = args.reviewed === true;
    const ref = await resolveEntryRef(exec, id);
    const entryId = ref?.entryId ?? id;
    await exec(
      reviewed
        ? "UPDATE entries SET reviewed_at = datetime('now') WHERE id = ?"
        : 'UPDATE entries SET reviewed_at = NULL WHERE id = ?',
      [entryId],
    );
    return;
  },
  markAllReviewed: async (exec, args: Args['markAllReviewed']) => {
    const ledgerId = str(args.ledgerId || 'personal');
    const accountId = args.accountId ? str(args.accountId) : null;
    if (accountId) {
      await exec(
        `UPDATE entries SET reviewed_at = datetime('now')
          WHERE ledger_id = ? AND reviewed_at IS NULL
            AND EXISTS (SELECT 1 FROM postings p WHERE p.entry_id = entries.id AND p.account_id = ?)`,
        [ledgerId, accountId],
      );
    } else {
      await exec(
        `UPDATE entries SET reviewed_at = datetime('now') WHERE ledger_id = ? AND reviewed_at IS NULL`,
        [ledgerId],
      );
    }
    return;
  },
  reconcileAccount: async (exec, args: Args['reconcileAccount']) => {
    const accountId = str(args.accountId);
    const statementBalance = Number(args.statementBalance);
    if (!Number.isFinite(statementBalance)) throw new I18nError('error.reconcile.statementBalance', {}, 'Statement balance is required');
    const statementDate = args.statementDate ? str(args.statementDate) : new Date().toISOString().slice(0, 10);
    const doPostAdjustment = args.postAdjustment === true;

    if (doPostAdjustment) {
      const [acct] = await exec('SELECT ledger_id FROM accounts WHERE id = ?', [accountId]);
      if (!acct) throw new I18nError('error.notFound.account', {}, 'Account not found');
      const [sum] = await exec(
        `SELECT COALESCE(SUM(p.amount), 0) AS s
           FROM postings p JOIN entries e ON e.id = p.entry_id
          WHERE p.account_id = ?
            AND e.status = 'confirmed'
            AND p.cleared_at IS NOT NULL`,
        [accountId],
      );
      const cleared = r2(Number(sum.s));
      const delta = r2(statementBalance - cleared);
      if (Math.abs(delta) >= 0.005) {
        const adjResult = await postAdjustment(exec, {
          ledgerId: String(acct.ledger_id),
          accountId,
          delta,
          date: statementDate,
          source: 'reconcile',
        });
        if (adjResult) {
          await exec(
            `UPDATE postings SET cleared_at = datetime('now')
              WHERE entry_id = ? AND account_id IS NOT NULL`,
            [adjResult.entryId],
          );
        }
      }
    }
    await exec(
      `UPDATE accounts
          SET last_reconciled_at = ?,
              last_reconciled_balance = ?,
              updated_at = datetime('now')
        WHERE id = ?`,
      [statementDate, statementBalance, accountId],
    );
    return;
  },
  bulkRecategorize: async (exec, args: Args['bulkRecategorize']) => {
    const ids = Array.isArray(args.ids) ? args.ids.map(str) : [];
    const categoryId = args.categoryId == null ? null : str(args.categoryId);
    if (!ids.length) return;

    const cats = new Set<string>();
    if (categoryId) cats.add(categoryId);
    let earliest = '';

    for (const id of ids) {
      const ref = await resolveEntryRef(exec, id);
      if (!ref) continue;
      const { entryId } = ref;

      const [entry] = await exec('SELECT date FROM entries WHERE id = ?', [entryId]);
      if (!entry) continue;
      const d = String(entry.date ?? '');
      if (d && (!earliest || d < earliest)) earliest = d;

      const catLegs = await exec(
        'SELECT category_id FROM postings WHERE entry_id = ? AND category_id IS NOT NULL',
        [entryId],
      );
      for (const leg of catLegs) cats.add(String(leg.category_id));

      const [acctLeg] = await exec(
        `SELECT id, account_id, amount, amount_base, exchange_rate, currency, cleared_at, memo
           FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1`,
        [entryId],
      );
      if (!acctLeg) continue;

      if (catLegs.length >= 2) continue;

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
      legs.push({ categoryId: categoryId ?? null, amountBase: -Number(acctLeg.amount_base) });
      await rebuildEntry(exec, entryId, { legs });
    }

    if (cats.size > 0 && earliest) {
      await invalidateRollover(exec, { categoryIds: [...cats], accountIds: [] }, earliest);
    }
    return;
  },
  deleteTransaction: async (exec, args: Args['deleteTransaction']) => {
    const id = str(args.id);
    const before = await txTouches(exec, id);
    const attachmentPaths = await getAttachmentRelPathsForTransaction(exec, id);
    await qDeleteTransactionRow(exec, id);
    if (before) {
      await invalidateRollover(
        exec,
        { categoryIds: before.categoryIds, accountIds: [before.accountId] },
        before.date,
      );
    }
    await unlinkAttachmentFiles(attachmentPaths);
    return;
  },
  removeAttachment: async (exec, args: Args['removeAttachment']) => {
    const id = str(args.id);
    const row = await getAttachmentFile(exec, id);
    if (!row) return;
    await deleteAttachment(exec, id);
    await unlinkAttachmentFiles([row.relPath]);
    return;
  },
  confirmTransaction: async (exec, args: Args['confirmTransaction']) => {
    await qConfirmTransaction(exec, str(args.id));
    return;
  },
  confirmPendingWithMerchant: async (exec, args: Args['confirmPendingWithMerchant']) => {
    await qConfirmPendingWithMerchant(exec, str(args.id), {
      counterpartyId: args.counterpartyId != null ? str(args.counterpartyId) : null,
      newCounterpartyName: args.newCounterpartyName != null ? str(args.newCounterpartyName) : null,
    });
    return;
  },
  confirmAllPending: async (exec, _args: Args['confirmAllPending']) => {
    const pendingAccts = await exec(
      `SELECT DISTINCT p.account_id
         FROM postings p JOIN entries e ON e.id = p.entry_id
        WHERE e.status = 'pending' AND p.account_id IS NOT NULL`,
    );
    await exec(
      "UPDATE entries SET status = 'confirmed', confirmed_at = ?, updated_at = datetime('now') WHERE status = 'pending'",
      [new Date().toISOString()],
    );
    for (const r of pendingAccts) await recomputeAccountFromPostings(exec, String(r.account_id));
    return;
  },
  setTransactionTags: async (exec, args: Args['setTransactionTags']) => {
    const txId = str(args.id);
    const tagIds = Array.isArray(args.tagIds) ? (args.tagIds as unknown[]).map(str) : [];
    // Resolve account-posting id → entry id; fall back to the id itself if
    // it already is an entry id (forward-compat with B4 callers).
    const ref = await resolveEntryRef(exec, txId);
    const entryId = ref?.entryId ?? txId;
    await exec('DELETE FROM entry_tags WHERE entry_id = ?', [entryId]);
    for (const tagId of tagIds) {
      await exec('INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)', [entryId, tagId]);
    }
    return;
  },
  setTransactionSplits: async (exec, args: Args['setTransactionSplits']) => {
    const txId = str(args.id);
    const rawSplits = Array.isArray(args.splits) ? (args.splits as unknown[]) : [];
    type SplitInput = { categoryId: string | null; amount: number; description: string | null };
    const splits: SplitInput[] = rawSplits.map((s) => {
      const o = s as Record<string, unknown>;
      return {
        categoryId: o.categoryId == null ? null : str(o.categoryId),
        amount: Number(o.amount),
        description: o.description == null ? null : str(o.description),
      };
    });

    const before = await txTouches(exec, txId);
    const ref = await resolveEntryRef(exec, txId);
    if (ref) {
      const { entryId } = ref;
      // Load the account leg — forward verbatim (amounts/account don't change).
      const [acctLeg] = await exec(
        `SELECT id, account_id, amount, amount_base, exchange_rate, cleared_at, memo
           FROM postings WHERE entry_id = ? AND account_id IS NOT NULL LIMIT 1`,
        [entryId],
      );
      if (acctLeg) {
        const totalBase = Math.abs(Number(acctLeg.amount_base));
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

        if (splits.length === 0) {
          // Clear splits: rebuild with a single uncategorised category leg.
          legs.push({ categoryId: null, amountBase: -Number(acctLeg.amount_base) });
        } else {
          // Must have at least two split rows to be meaningful.
          if (splits.length === 1) {
            throw new I18nError('error.split.minTwo', {}, 'Splits require at least two rows');
          }
          // Validate that splits sum matches the account leg magnitude.
          const splitTotal = splits.reduce((acc, sp) => acc + Math.abs(sp.amount), 0);
          if (splitTotal > 0 && Math.abs(splitTotal - totalBase) > 0.005 * splits.length) {
            throw new I18nError('error.split.sumMismatch', {}, 'Split amounts must sum to the transaction total');
          }
          // Compute base ratio: if amounts in native currency, scale to base.
          const baseRatio = splitTotal > 0 ? totalBase / splitTotal : 1;
          // Last leg absorbs rounding remainders.
          let usedBase = 0;
          for (let i = 0; i < splits.length; i++) {
            const sp = splits[i];
            const isLast = i === splits.length - 1;
            const spBase = isLast
              ? r2(Number(acctLeg.amount_base) + usedBase) // absorb remainder (signed)
              : r2(-Math.abs(sp.amount) * baseRatio * Math.sign(Number(acctLeg.amount_base)));
            if (!isLast) usedBase += spBase;
            legs.push({
              categoryId: sp.categoryId,
              amountBase: spBase,
              memo: sp.description,
            });
          }
        }
        await rebuildEntry(exec, entryId, { legs });
      }
    }
    const after = await txTouches(exec, txId);
    const merged = mergeTouches(before, after);
    if (merged) {
      await invalidateRollover(
        exec,
        { categoryIds: merged.categoryIds, accountIds: merged.accountIds },
        merged.earliestDate,
      );
    }
    return;
  },
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
