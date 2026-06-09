import { test, expect } from 'bun:test';
import { applyMutation } from '@/lib/db/mutate';
import { seededAndAudited } from '@/lib/db/core/test-utils';
import { I18nError } from '@/lib/i18n-error';
import { listCategories, monthlyByCategory, categorySpend } from '@/lib/db/queries/categories';

test('createCategory allows depth-3 (parent under a child) but rejects depth-4', async () => {
  const exec = await seededAndAudited();

  // Depth 3 OK: food (1) -> food-coffee (2) -> Espresso (3)
  await applyMutation(exec, 'createCategory', {
    ledgerId: 'personal', name: 'Espresso', parentId: 'food-coffee',
  });
  const cats = await listCategories(exec, 'personal');
  const espresso = cats.find((c) => c.name === 'Espresso')!;
  expect(espresso.parentId).toBe('food-coffee');

  // Depth 4 rejected.
  await expect(
    applyMutation(exec, 'createCategory', {
      ledgerId: 'personal', name: 'Doppio', parentId: espresso.id,
    }),
  ).rejects.toThrow(/three levels/i);
});

test('createCategory throws I18nError when parent is already at depth 3', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createCategory', {
    ledgerId: 'personal', name: 'Espresso', parentId: 'food-coffee',
  });
  const cats = await listCategories(exec, 'personal');
  const espresso = cats.find((c) => c.name === 'Espresso')!;
  await expect(
    applyMutation(exec, 'createCategory', {
      ledgerId: 'personal', name: 'Doppio', parentId: espresso.id,
    }),
  ).rejects.toThrow(I18nError);
});

test('updateCategory subtree move: depth-3 subtree fits only under a top-level parent', async () => {
  const exec = await seededAndAudited();

  // Build a depth-3 chain under food: food -> food-coffee -> Espresso.
  await applyMutation(exec, 'createCategory', {
    ledgerId: 'personal', name: 'Espresso', parentId: 'food-coffee',
  });

  // Try to move food-coffee (depth 2, with a depth-3 child) under
  // food-groceries (also depth 2). Would push Espresso to depth 4 -> reject.
  await expect(
    applyMutation(exec, 'updateCategory', {
      id: 'food-coffee', patch: { parentId: 'food-groceries' },
    }),
  ).rejects.toThrow(/three levels/i);

  // Same subtree under a TOP-LEVEL parent (rent) is fine — chain becomes
  // rent -> food-coffee -> Espresso, depth 3.
  await applyMutation(exec, 'updateCategory', {
    id: 'food-coffee', patch: { parentId: 'rent' },
  });
  const cats = await listCategories(exec, 'personal');
  expect(cats.find((c) => c.id === 'food-coffee')!.parentId).toBe('rent');
});

test('updateCategory rejects moving a node under its own descendant (cycle)', async () => {
  const exec = await seededAndAudited();
  await expect(
    applyMutation(exec, 'updateCategory', {
      id: 'food', patch: { parentId: 'food-coffee' },
    }),
  ).rejects.toThrow(/descendant/i);
});

test('deleteCategory promotes children to top-level (ON DELETE SET NULL)', async () => {
  const exec = await seededAndAudited();
  // 'food' has demo children. Delete it; the children should survive as top-level.
  await applyMutation(exec, 'deleteCategory', { id: 'food' });
  const after = await listCategories(exec, 'personal');
  const groceries = after.find((c) => c.id === 'food-groceries')!;
  expect(groceries).toBeTruthy();
  expect(groceries.parentId).toBeNull();
});

test('createCategory inserts a ledger-scoped category', async () => {
  const exec = await seededAndAudited();
  const before = Number((await exec("SELECT count(*) AS n FROM categories WHERE ledger_id = 'personal'"))[0].n);
  await applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: 'Travel', type: 'expense', icon: 'plane' });
  const rows = await exec("SELECT * FROM categories WHERE name = 'Travel' AND ledger_id = 'personal'");
  expect(rows.length).toBe(1);
  expect(String(rows[0].kind)).toBe('expense');
  expect(String(rows[0].icon)).toBe('plane');
  const after = Number((await exec("SELECT count(*) AS n FROM categories WHERE ledger_id = 'personal'"))[0].n);
  expect(after).toBe(before + 1);
});

test('createCategory rejects an empty name', async () => {
  const exec = await seededAndAudited();
  await expect(applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: '  ' })).rejects.toThrow();
});

test('updateCategory edits name/type/icon/color', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'updateCategory', { id: 'food', patch: { name: 'Food & Drink', type: 'income', icon: 'coins', color: '#8085dc' } });
  const [c] = await exec("SELECT name, kind, icon, color FROM categories WHERE id = 'food'");
  expect(String(c.name)).toBe('Food & Drink');
  expect(String(c.kind)).toBe('income');
  expect(String(c.icon)).toBe('coins');
  expect(String(c.color)).toBe('#8085dc');
});

test('createCategory persists icon + color, and listCategories returns color', async () => {
  const exec = await seededAndAudited();
  await applyMutation(exec, 'createCategory', { ledgerId: 'personal', name: 'Travel', type: 'expense', icon: 'car', color: '#00a6ae' });
  const cat = (await listCategories(exec, 'personal')).find((c) => c.name === 'Travel')!;
  expect(cat.icon).toBe('car');
  expect(cat.color).toBe('#00a6ae');
  // Seeded categories keep their JSON color too.
  expect((await listCategories(exec, 'personal')).find((c) => c.id === 'food')!.color).toBe('#d16b7a');
});

test('deleteCategory uncategorizes its transactions', async () => {
  const exec = await seededAndAudited();
  const before = Number((await exec("SELECT COUNT(*) AS n FROM categories WHERE id = 'food'"))[0].n);
  expect(before).toBe(1);
  // §2: category is referenced by postings (category_id FK with SET NULL).
  const tagged = Number((await exec("SELECT COUNT(*) AS n FROM postings WHERE category_id = 'food'"))[0].n);
  expect(tagged).toBeGreaterThan(0);
  await applyMutation(exec, 'deleteCategory', { id: 'food' });
  expect(Number((await exec("SELECT COUNT(*) AS n FROM categories WHERE id = 'food'"))[0].n)).toBe(0);
  // FK is SET NULL on postings: those postings survive but become uncategorized.
  expect(Number((await exec("SELECT COUNT(*) AS n FROM postings WHERE category_id = 'food'"))[0].n)).toBe(0);
});

test('deleteCategory: scheduled_templates.category_id is SET NULL (used to be RESTRICT)', async () => {
  const exec = await seededAndAudited();
  // §2: scheduled_templates.kind uses the entry kind values (expense/income/etc).
  await exec(
    `INSERT INTO scheduled_templates
       (id, ledger_id, name, kind, account_id, category_id, frequency,
        start_date, created_at, updated_at)
     VALUES ('sch-food','personal','Weekly groceries','expense','chk','food','weekly',
             '2026-05-01', datetime('now'), datetime('now'))`,
  );
  // Pre-fix this would throw "FOREIGN KEY constraint failed" (RESTRICT).
  await applyMutation(exec, 'deleteCategory', { id: 'food' });
  const [row] = await exec("SELECT category_id FROM scheduled_templates WHERE id = 'sch-food'");
  expect(row.category_id).toBeNull();
});

test('categories: list + monthly spend', async () => {
  const exec = await seededAndAudited();
  expect((await listCategories(exec, 'personal')).length).toBe(15); // 8 top-level + 7 demo subcategories
  const spend = await monthlyByCategory(exec, 'personal', '2026-05');
  const food = spend.find((c) => c.id === 'food')!;
  expect(food.spent).toBeGreaterThan(0);
  // Food spend should equal the sum of confirmed food expenses.
  expect(food.spent).toBeCloseTo(6.75 + 84.32 + 42.18 + 14.2 + 29.84, 2);

  // All-time map spans the full seed history — the prior-year `h*` rows
  // (groceries + dining) push the total well above the original Mar/Apr/May
  // sum; assert at least that minimum so it stays a meaningful regression test.
  const map = await categorySpend(exec, 'personal');
  expect(map.food).toBeGreaterThanOrEqual(6.75 + 84.32 + 42.18 + 14.2 + 29.84 + 132.8 + 96.5);
});

test('categories: 2-level tree — parent_id wires children, build+rollup behave', async () => {
  const exec = await seededAndAudited();
  const { buildCategoryTree, rollupCategorySpend } = await import('@/lib/db/queries/categories');
  const cats = await listCategories(exec, 'personal');

  // Seeded demo children carry their parent id.
  const groceries = cats.find((c) => c.id === 'food-groceries')!;
  expect(groceries.parentId).toBe('food');
  const food = cats.find((c) => c.id === 'food')!;
  expect(food.parentId).toBeNull();

  // Tree groups children under their parent; childless parents come back with [].
  const tree = buildCategoryTree(cats);
  const foodNode = tree.find((n) => n.parent.id === 'food')!;
  expect(foodNode.children.map((c) => c.id).sort()).toEqual(
    ['food-coffee', 'food-groceries', 'food-restaurants'].sort(),
  );
  expect(tree.find((n) => n.parent.id === 'rent')!.children).toEqual([]);

  // rollupCategorySpend folds child totals into the parent bucket.
  const rolled = rollupCategorySpend({ food: 10, 'food-groceries': 30, 'food-coffee': 5 }, cats);
  expect(rolled.food).toBe(10 + 30 + 5);
  expect(rolled['food-groceries']).toBe(30); // children keep their own line too
});

test('rollupCategorySpend folds grandchild → child → parent (3-level)', async () => {
  // Synthetic 3-level tree so the test is independent of the seed.
  const cats = [
    { id: 'food',  parentId: null },
    { id: 'rest',  parentId: 'food' },
    { id: 'japan', parentId: 'rest' },
  ];
  const { rollupCategorySpend } = await import('@/lib/db/queries/categories');
  const rolled = rollupCategorySpend({ food: 10, rest: 20, japan: 30 }, cats);
  expect(rolled.japan).toBe(30);          // leaf stays alone
  expect(rolled.rest).toBe(20 + 30);       // child = own + grandchild
  expect(rolled.food).toBe(10 + 20 + 30);  // root = own + child + grandchild
});

test('expandDescendants returns the configured ids plus every descendant', async () => {
  const cats = [
    { id: 'food',     parentId: null },
    { id: 'rest',     parentId: 'food' },
    { id: 'japan',    parentId: 'rest' },
    { id: 'thai',     parentId: 'rest' },
    { id: 'grocery',  parentId: 'food' },
    { id: 'rent',     parentId: null },
  ];
  const { expandDescendants } = await import('@/lib/db/queries/categories');
  const set = expandDescendants(['food'], cats);
  expect(set).toEqual(new Set(['food', 'rest', 'japan', 'thai', 'grocery']));
  // Already-deep ids stay (no double-add).
  expect(expandDescendants(['japan'], cats)).toEqual(new Set(['japan']));
  // Multiple roots merge.
  expect(expandDescendants(['food', 'rent'], cats)).toEqual(
    new Set(['food', 'rest', 'japan', 'thai', 'grocery', 'rent']),
  );
});
