import { test, expect } from '@playwright/test';

test('root redirects to accounts and shows net worth', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveURL(/\/accounts$/);
  await expect(page.getByText('Net worth · all accounts')).toBeVisible();
});

test('add expense flows into Activity', async ({ page }) => {
  await page.goto('/add');
  await page.getByLabel('Amount').fill('42');
  await page.getByLabel('Merchant').fill('E2E Coffee');
  await page.getByRole('button', { name: 'Save expense' }).click();
  await page.waitForURL('**/activity');
  // Desktop viewport renders the transactions table; assert the visible cell.
  await expect(page.getByRole('cell', { name: /E2E Coffee/ })).toBeVisible();
});

test('splitting a transaction reduces its amount', async ({ page }) => {
  await page.goto('/tx/t02'); // Whole Foods Market · −$84.32
  await page.getByRole('button', { name: 'Split' }).click();
  await page.getByLabel('Split amount').fill('20');
  await page.getByRole('dialog').getByRole('button', { name: 'Split' }).click();
  await expect(page.getByText('Transaction split')).toBeVisible(); // success toast
  await expect(page.getByRole('dialog')).toHaveCount(0); // dialog closed
  await expect(page.getByText('$64.32')).toBeVisible();
});

test('theme toggle switches to dark', async ({ page }) => {
  await page.goto('/settings');
  await page.getByRole('button', { name: 'Toggle theme' }).first().click();
  await expect(page.locator('html')).toHaveClass(/dark/);
});
