import { test, expect } from 'bun:test';
import { applyMutation } from '@/lib/db/mutate';
import { seededAndAudited } from './test-utils';
import { migrate, SCHEMA_VERSION } from './schema';
import { legacyMonthStepOccurrences, repairQuarterlyStartDays } from './repair-quarterly-start-day';
import { listScheduled } from '@/lib/db/queries/scheduled';
import { occurrencesUpTo } from '@/lib/recurrence';
import type { Exec } from './repo';

// A quarterly or yearly template saved before #817 stores day_of_month = 1 and was
// posted on the 1st; #817 recurs on the start date's day, so that history matches
// nothing and generateDueScheduled books the new dates again. The repair moves the
// start onto the first date the old rule produced. Mirrors FinchCore's
// QuarterlyStartDayRepairTests.

const TODAY = '2026-10-19';

async function create(exec: Exec, extra: Record<string, unknown> = {}) {
  await applyMutation(exec, 'createScheduled', {
    id: 'ins', ledgerId: 'personal', name: 'Insurance', type: 'expense', amount: 180,
    frequency: 'quarterly', dayOfMonth: 1, accountId: 'cc', startDate: '2026-03-15', ...extra,
  });
}

async function post(exec: Exec, ...dates: string[]) {
  for (const date of dates) {
    await applyMutation(exec, 'postScheduled', { templateId: 'ins', date, occurrenceDate: date, time: '09:00' });
  }
}

async function row(exec: Exec) {
  const [r] = await exec(`SELECT start_date, day_of_month, updated_at FROM scheduled_templates WHERE id = 'ins'`);
  return { start: String(r.start_date), day: Number(r.day_of_month), updated: String(r.updated_at) };
}

async function keys(exec: Exec) {
  return (await exec(
    `SELECT COALESCE(occurrence_date, date) AS d FROM entries WHERE source_template_id = 'ins' ORDER BY 1`,
  )).map((r) => String(r.d));
}

async function template(exec: Exec) {
  return (await listScheduled(exec, 'personal')).find((t) => t.id === 'ins')!;
}

const generate = (exec: Exec, today = TODAY) => applyMutation(exec, 'generateDueScheduled', { today, time: '09:00' });

test('without the repair, the load-time generator books the new dates again', async () => {
  const exec = await seededAndAudited();
  await create(exec);
  await post(exec, '2026-06-01', '2026-09-01');
  await generate(exec);
  expect(await keys(exec)).toEqual(['2026-03-15', '2026-06-01', '2026-06-15', '2026-09-01', '2026-09-15']);
});

test('the repair moves the start to the first date it ran, and the generator adds nothing', async () => {
  const exec = await seededAndAudited();
  await create(exec);
  await post(exec, '2026-06-01', '2026-09-01');
  await repairQuarterlyStartDays(exec);
  expect(await row(exec)).toMatchObject({ start: '2026-06-01', day: 1 });
  expect(occurrencesUpTo(await template(exec), TODAY)).toEqual(['2026-06-01', '2026-09-01']);
  await generate(exec);
  expect(await keys(exec)).toEqual(['2026-06-01', '2026-09-01']);
});

test('migrate runs it on a database stamped before it', async () => {
  const exec = await seededAndAudited();
  await create(exec);
  await post(exec, '2026-06-01');
  await exec('DELETE FROM db_metadata');
  await exec(
    `INSERT INTO db_metadata (id,app_name,schema_version,app_version,created_at,updated_at)
     VALUES (1,'finch','2026-08-12T01:00:00Z','0.1.0','seed','seed')`,
  );
  await migrate(exec, { fresh: false });
  expect((await row(exec)).start).toBe('2026-06-01');
  const [m] = await exec('SELECT schema_version FROM db_metadata WHERE id = 1');
  expect(String(m.schema_version)).toBe(SCHEMA_VERSION);
});

test('running it again changes nothing', async () => {
  const exec = await seededAndAudited();
  await create(exec);
  await post(exec, '2026-06-01', '2026-09-01');
  await repairQuarterlyStartDays(exec);
  const once = await row(exec);
  await exec(`UPDATE scheduled_templates SET updated_at = 'sentinel' WHERE id = 'ins'`);
  await repairQuarterlyStartDays(exec);
  expect(await row(exec)).toEqual({ ...once, updated: 'sentinel' });
});

test('yearly', async () => {
  const exec = await seededAndAudited();
  await create(exec, { frequency: 'yearly', startDate: '2025-03-15' });
  await post(exec, '2026-03-01');
  await repairQuarterlyStartDays(exec);
  expect((await row(exec)).start).toBe('2026-03-01');
});

test('a start on the 1st, no history, monthly, and new-rule history are left alone', async () => {
  for (const [extra, posted] of [
    [{ startDate: '2026-03-01' }, ['2026-03-01', '2026-06-01']],
    [{}, []],
    [{ frequency: 'monthly' }, ['2026-04-01']],
    [{}, ['2026-03-15', '2026-06-15']],
  ] as [Record<string, unknown>, string[]][]) {
    const exec = await seededAndAudited();
    await create(exec, extra);
    await post(exec, ...posted);
    const before = await row(exec);
    await repairQuarterlyStartDays(exec);
    expect(await row(exec)).toEqual(before);
  }
});

test('an installment plan keeps its remaining count and its end date', async () => {
  const exec = await seededAndAudited();
  await create(exec, { installmentTotal: 4, endDate: '2027-06-30' });
  await post(exec, '2026-06-01', '2026-09-01');
  await repairQuarterlyStartDays(exec);
  await generate(exec, '2027-12-31');
  expect(await keys(exec)).toEqual(['2026-06-01', '2026-09-01', '2026-12-01', '2027-03-01']);
  expect((await template(exec)).endDate).toBe('2027-06-30');
});

test('max_executions keeps its remaining count', async () => {
  const exec = await seededAndAudited();
  await create(exec, { maxExecutions: 3 });
  await post(exec, '2026-06-01');
  await repairQuarterlyStartDays(exec);
  await generate(exec, '2027-12-31');
  expect(await keys(exec)).toEqual(['2026-06-01', '2026-09-01', '2026-12-01']);
});

test('a native skip in app_state counts as history', async () => {
  const exec = await seededAndAudited();
  await create(exec);
  await exec(
    `INSERT INTO app_state (key,value,created_at,updated_at) VALUES ('scheduledSkips', ?, 'x', 'x')`,
    [JSON.stringify({ ins: ['2026-06-01'] })],
  );
  await repairQuarterlyStartDays(exec);
  expect((await row(exec)).start).toBe('2026-06-01');
});

test('a time after the start day is kept', async () => {
  const exec = await seededAndAudited();
  await create(exec, { startDate: '2026-03-15T09:30' });
  await post(exec, '2026-06-01');
  await repairQuarterlyStartDays(exec);
  expect((await row(exec)).start).toBe('2026-06-01T09:30');
});

test('a clamped first date: the start goes to the stored day when nothing before it is owed', async () => {
  const exec = await seededAndAudited();
  await create(exec, { startDate: '2026-04-10', dayOfMonth: 31 });
  await post(exec, '2026-04-30', '2026-07-31');
  await repairQuarterlyStartDays(exec);
  expect(await row(exec)).toMatchObject({ start: '2026-07-31', day: 31 });
  await generate(exec);
  expect(await keys(exec)).toEqual(['2026-04-30', '2026-07-31']);
});

test('a clamped first date that is still owed stays in the series', async () => {
  const exec = await seededAndAudited();
  await create(exec, { startDate: '2026-04-10', dayOfMonth: 31 });
  await post(exec, '2026-07-31');
  await repairQuarterlyStartDays(exec);
  expect(await row(exec)).toMatchObject({ start: '2026-04-30', day: 30 });
});

test('legacyMonthStepOccurrences matches the pre-#817 engine', () => {
  expect(legacyMonthStepOccurrences('2026-03-15', 1, 3, null, '2026-12-31'))
    .toEqual(['2026-06-01', '2026-09-01', '2026-12-01']);
  expect(legacyMonthStepOccurrences('2026-01-10', 31, 3, '2026-10-30', '2027-01-31'))
    .toEqual(['2026-01-31', '2026-04-30', '2026-07-31']);
  expect(legacyMonthStepOccurrences('2027-02-10', 29, 12, null, '2029-12-31'))
    .toEqual(['2027-02-28', '2028-02-29', '2029-02-28']);
});
