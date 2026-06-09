import { test, expect } from 'bun:test';
import { applyMutation } from '@/lib/db/mutate';
import { seededAndAudited } from '@/lib/db/core/test-utils';
import type { Exec } from '@/lib/db/core/repo';
import { listScheduled } from '@/lib/db/queries/scheduled';

const balanceOf = async (exec: Exec, id: string) =>
  Number((await exec('SELECT current_balance AS b FROM accounts WHERE id = ?', [id]))[0].b);

const installmentPaidOf = async (exec: Exec, id: string) => {
  const all = await listScheduled(exec, 'personal');
  return all.find((t) => t.id === id)?.installmentPaid ?? -1;
};

test('postScheduled posts a resolvable expense template as a transaction', async () => {
  const exec = await seededAndAudited();
  // rt-spotify: $11.99 expense on "Amex Gold" → account cc.
  const ccBefore = await balanceOf(exec, 'cc');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-spotify' });
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(ccBefore - 11.99, 2);
  // §2: entries replaces transactions; amount is on the account posting.
  const rows = await exec(
    "SELECT e.kind, p.amount FROM entries e JOIN postings p ON p.entry_id = e.id WHERE e.description = 'Spotify Premium' AND p.account_id IS NOT NULL",
  );
  expect(rows.length).toBe(1);
  expect(Number(rows[0].amount)).toBeCloseTo(-11.99, 2);
  expect(String(rows[0].kind)).toBe('expense');
});

test('postScheduled stamps the template category onto the posted transaction', async () => {
  const exec = await seededAndAudited();
  // Build a template that has a category set, then post it manually. The
  // posted row should carry that category — earlier the manual-post path
  // hard-coded category_id to NULL while autopost preserved it.
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-cat', name: 'Coffee subscription', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'cc', amount: 12, category: 'food',
  });
  await applyMutation(exec, 'postScheduled', { templateId: 'sch-cat' });
  // §2: category is on the category posting (account_id IS NULL); entry carries source_template_id.
  const [row] = await exec(
    "SELECT p.category_id FROM postings p JOIN entries e ON e.id = p.entry_id WHERE e.source_template_id = 'sch-cat' AND p.account_id IS NULL AND p.category_id IS NOT NULL LIMIT 1",
  );
  expect(String(row.category_id)).toBe('food');
});

test('postScheduled posts to the template\'s linked account', async () => {
  const exec = await seededAndAudited();
  // rt-rent: $1850 expense on Chase Checking (chk).
  const chkBefore = await balanceOf(exec, 'chk');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-rent' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chkBefore - 1850, 2);
});

test('postScheduled splits income across its linked accounts', async () => {
  const exec = await seededAndAudited();
  // rt-salary: $5800 income split 60/25/15 across Chase Checking / Marcus Savings / Fidelity Brokerage.
  const chkBefore = await balanceOf(exec, 'chk');
  const savBefore = await balanceOf(exec, 'sav');
  const invBefore = await balanceOf(exec, 'inv');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-salary' });
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chkBefore + 5800 * 0.60, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(savBefore + 5800 * 0.25, 2);
  expect(await balanceOf(exec, 'inv')).toBeCloseTo(invBefore + 5800 * 0.15, 2);
});

test('updateScheduledSplit updates the nth split by sort order', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'updateScheduledSplit', { templateId: 'rt-salary', index: 1, pct: 30 });
  const rows = await exec("SELECT amount_pct FROM scheduled_splits WHERE template_id = 'rt-salary' ORDER BY sort_order");
  expect(Number(rows[0].amount_pct)).toBe(60); // unchanged
  expect(Number(rows[1].amount_pct)).toBe(30); // updated
});

test('deleteScheduled removes the template and cascades its splits', async () => {
  const exec = await seededAndAudited();
  expect(Number((await exec("SELECT COUNT(*) AS n FROM scheduled_splits WHERE template_id = 'rt-salary'"))[0].n)).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteScheduled', { id: 'rt-salary' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM scheduled_templates WHERE id = 'rt-salary'"))[0].n)).toBe(0);
  expect(Number((await exec("SELECT COUNT(*) AS n FROM scheduled_splits WHERE template_id = 'rt-salary'"))[0].n)).toBe(0);
});

test('updateScheduled silently skips unknown keys without throwing a SQL error', async () => {
  const exec = await seededAndAudited();
  // A stray patch key (typo, stale field name) used to become `undefined = ?`
  // in SQL and throw "near '=': syntax error". The query should ignore it and
  // apply the known fields cleanly.
  await applyMutation(exec, 'updateScheduled', {
    id: 'rt-spotify',
    patch: { name: 'Spotify Family', unknownField: 'noise', anotherTypo: 42 },
  });
  const [r] = await exec("SELECT name FROM scheduled_templates WHERE id = 'rt-spotify'");
  expect(String(r.name)).toBe('Spotify Family');
});

test('createScheduled inserts a template that lists and posts', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createScheduled', {
    id: 'rt-new', ledgerId: 'personal', name: 'Netflix', type: 'expense',
    amount: 19.99, frequency: 'monthly', dayOfMonth: 9, accountId: 'cc', autoPost: true, weekDay: null, color: null,
  });
  const t = (await listScheduled(exec, 'personal')).find((r) => r.id === 'rt-new')!;
  expect(t.name).toBe('Netflix');
  expect(t.amount).toBeCloseTo(19.99, 2);
  expect(t.frequency).toBe('monthly');
  expect(t.account).toBe('Amex Gold');
  const ccBefore = await balanceOf(exec, 'cc');
  await applyMutation(exec, 'postScheduled', { templateId: 'rt-new' });
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(ccBefore - 19.99, 2);

  await expect(applyMutation(exec, 'createScheduled', { name: 'X', type: 'expense', frequency: 'monthly', accountId: '' })).rejects.toThrow();
  await expect(applyMutation(exec, 'createScheduled', { name: 'Y', type: 'nope', accountId: 'cc' })).rejects.toThrow();
});

test('addScheduledSplit / removeScheduledSplit manage splits + splits_enabled', async () => {
  const exec = await seededAndAudited();
  // rt-spotify has no splits seeded.
  const flag = async () => Number((await exec("SELECT splits_enabled FROM scheduled_templates WHERE id = 'rt-spotify'"))[0].splits_enabled);
  expect(await flag()).toBe(0);

  await applyMutation(exec, 'addScheduledSplit', { templateId: 'rt-spotify', accountId: 'sav', pct: 40 });
  await applyMutation(exec, 'addScheduledSplit', { templateId: 'rt-spotify', accountId: 'inv', pct: 60 });
  let t = (await listScheduled(exec, 'personal')).find((r) => r.id === 'rt-spotify')!;
  expect(t.splits?.map((s) => s.account)).toEqual(['Marcus Savings', 'Fidelity Brokerage']);
  expect(t.splits?.map((s) => s.pct)).toEqual([40, 60]);
  expect(await flag()).toBe(1);

  // Remove the first split (by index/sort order).
  await applyMutation(exec, 'removeScheduledSplit', { templateId: 'rt-spotify', index: 0 });
  t = (await listScheduled(exec, 'personal')).find((r) => r.id === 'rt-spotify')!;
  expect(t.splits?.map((s) => s.account)).toEqual(['Fidelity Brokerage']);
  expect(await flag()).toBe(1);

  // Removing the last one clears the split-enabled flag.
  await applyMutation(exec, 'removeScheduledSplit', { templateId: 'rt-spotify', index: 0 });
  t = (await listScheduled(exec, 'personal')).find((r) => r.id === 'rt-spotify')!;
  expect(t.splits ?? []).toEqual([]);
  expect(await flag()).toBe(0);

  await expect(applyMutation(exec, 'addScheduledSplit', { templateId: 'rt-spotify', accountId: '  ' })).rejects.toThrow();
});

test('createScheduled rejects an installment total that isn\'t a positive integer', async () => {
  const exec = await seededAndAudited();
  await expect(
    applyMutation(exec, 'createScheduled', {
      id: 'sch-bad', name: 'Bad plan', type: 'expense', frequency: 'monthly',
      dayOfMonth: 1, accountId: 'chk', amount: 100, installmentTotal: 0,
    }),
  ).rejects.toThrow('Installment total must be a positive whole number');
  await expect(
    applyMutation(exec, 'createScheduled', {
      id: 'sch-bad2', name: 'Bad plan 2', type: 'expense', frequency: 'monthly',
      dayOfMonth: 1, accountId: 'chk', amount: 100, installmentTotal: 1.5,
    }),
  ).rejects.toThrow('Installment total must be a positive whole number');
});

test('postScheduled blocks once installmentPaid reaches installmentTotal', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-phone', name: 'Phone contract', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'chk', amount: 50, installmentTotal: 2,
  });
  await applyMutation(exec, 'postScheduled', { templateId: 'sch-phone' });
  expect(await installmentPaidOf(exec, 'sch-phone')).toBe(1);
  await applyMutation(exec, 'postScheduled', { templateId: 'sch-phone' });
  expect(await installmentPaidOf(exec, 'sch-phone')).toBe(2);
  // The plan is now full; a third post should be rejected.
  await expect(
    applyMutation(exec, 'postScheduled', { templateId: 'sch-phone' }),
  ).rejects.toThrow('finished its 2-payment plan');
});

test('installmentPaid counts only CONFIRMED transactions; cancelling a pending leaves it untouched', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-plan', name: 'Furniture 0%', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'chk', amount: 200, installmentTotal: 12,
    autoPost: true, startDate: '2026-01-01',
  });
  // generateDueScheduled creates pending rows — they shouldn't count toward
  // "paid" (the user hasn't confirmed them yet).
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-03-15' });
  // §2: entries replaces transactions.
  const pendingBefore = await exec(
    "SELECT id FROM entries WHERE source_template_id = 'sch-plan' AND status = 'pending'",
  );
  expect(pendingBefore.length).toBeGreaterThan(0);
  expect(await installmentPaidOf(exec, 'sch-plan')).toBe(0);
  // Confirming one of them moves the counter by exactly one.
  await applyMutation(exec, 'confirmTransaction', { id: String(pendingBefore[0].id) });
  expect(await installmentPaidOf(exec, 'sch-plan')).toBe(1);
  // Cancelling another pending row leaves the counter untouched.
  await applyMutation(exec, 'deleteTransaction', { id: String(pendingBefore[1].id) });
  expect(await installmentPaidOf(exec, 'sch-plan')).toBe(1);
});

test('generateDueScheduled stops generating once the plan has filled installmentTotal', async () => {
  const exec = await seededAndAudited();
  // 3-month plan starting Jan 2026, daily would over-shoot, monthly is right.
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-cap', name: 'Three-month plan', type: 'expense', frequency: 'monthly',
    dayOfMonth: 1, accountId: 'chk', amount: 100, installmentTotal: 3,
    autoPost: true, startDate: '2026-01-01',
  });
  // After a year, only 3 occurrences should exist (Jan, Feb, Mar) — the cap
  // wins even though monthly occurrences would otherwise have generated 12.
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-12-31' });
  // §2: entries replaces transactions.
  const gen = await exec(
    "SELECT id FROM entries WHERE source_template_id = 'sch-cap'",
  );
  expect(gen.length).toBe(3);
});

test('generateDueScheduled materializes due occurrences, idempotently', async () => {
  const exec = await seededAndAudited();
  const cc0 = await balanceOf(exec, 'cc');
  const chk0 = await balanceOf(exec, 'chk');
  const sav0 = await balanceOf(exec, 'sav');

  await applyMutation(exec, 'generateDueScheduled', { today: '2026-05-30' });
  // rt-spotify (cc, day 22), rt-icloud (cc, day 8), rt-rent (chk, day 1) →
  // 3 pending expense entries. rt-sweep (chk → sav, day 28) → 1 confirmed
  // transfer entry with 2 account postings.
  // §2: entries replace transactions; 1 expense entry = 1 entry (not 2 rows).
  // For transfers: 1 entry, but we check by source_template_id on entries.
  const gen = await exec(
    "SELECT id, status, source_template_id AS t FROM entries WHERE source_template_id IS NOT NULL ORDER BY date",
  );
  // 3 expense entries + 1 transfer entry = 4 total entries.
  expect(gen.length).toBe(4);
  const pending = gen.filter((r) => String(r.status) === 'pending');
  const confirmed = gen.filter((r) => String(r.status) === 'confirmed');
  expect(pending.length).toBe(3); // expense entries stay pending
  expect(confirmed.length).toBe(1); // 1 transfer entry confirmed
  expect(confirmed.every((r) => String(r.t) === 'rt-sweep')).toBe(true);
  // Pending didn't touch cc; the confirmed sweep moved chk and sav.
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(cc0, 2);
  expect(await balanceOf(exec, 'chk')).toBeCloseTo(chk0 - 800, 2);
  expect(await balanceOf(exec, 'sav')).toBeCloseTo(sav0 + 800, 2);

  // Idempotent: a second run adds nothing (dedup via source_template_id + date).
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-05-30' });
  const again = await exec("SELECT id FROM entries WHERE source_template_id IS NOT NULL");
  expect(again.length).toBe(4);

  // Confirming the Spotify pending (11.99 expense) pulls it into cc's balance.
  const spotify = gen.find((r) => String(r.t) === 'rt-spotify')!;
  await applyMutation(exec, 'confirmTransaction', { id: String(spotify.id) });
  expect(await balanceOf(exec, 'cc')).toBeCloseTo(cc0 - 11.99, 2);
});

test('generateDueScheduled: recurring transfer caps at installment_total like other templates', async () => {
  const exec = await seededAndAudited();
  // 3-payment recurring transfer; after a year only 3 occurrences should fire
  // (Jan, Feb, Mar 2026). §2: each occurrence = 1 transfer entry (not 2 rows).
  await applyMutation(exec, 'createScheduled', {
    id: 'sch-recur-xfer', name: 'Auto-savings', type: 'transfer',
    frequency: 'monthly', dayOfMonth: 5, accountId: 'sav', fromAccountId: 'chk',
    amount: 200, installmentTotal: 3, autoPost: true, startDate: '2026-01-01',
  });
  await applyMutation(exec, 'generateDueScheduled', { today: '2026-12-31' });
  // §2: entries replaces transactions; 3 transfer entries, each with 2 postings.
  const entries = await exec(
    "SELECT id FROM entries WHERE source_template_id = 'sch-recur-xfer'",
  );
  expect(entries.length).toBe(3); // 3 transfer entries (one per occurrence)
  // Each transfer entry has 2 account postings (from + to leg).
  const postings = await exec(
    "SELECT p.id FROM postings p JOIN entries e ON p.entry_id = e.id WHERE e.source_template_id = 'sch-recur-xfer' AND p.account_id IS NOT NULL",
  );
  expect(postings.length).toBe(6); // 3 entries × 2 postings
});
