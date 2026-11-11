import { test, expect } from '@playwright/test';
import type { fixture } from './app';
// @ts-expect-error Repository helper is JavaScript.
import { loadEnv } from '../../lib/load-env.mjs';
loadEnv();
declare global { interface Window { fixture: typeof fixture } }

test('real WASM, StrictMode, query replacement, cleanup, remount, reload data loss', async ({ page }) => {
  const license = process.env.DITTO_OFFLINE_LICENSE;
  if (!license) throw new Error('Set DITTO_OFFLINE_LICENSE');
  const config = { license, databaseID: process.env.DITTO_DATABASE_ID ?? '00000000-0000-4000-8000-000000000001' };
  await page.goto('/');
  await page.evaluate(config => window.fixture.start(config), config);
  await expect(page.locator('output')).toHaveText('Empty');
  await page.evaluate(() => window.fixture.write());
  await expect(page.locator('output')).toHaveText('Browser task');
  expect(await page.evaluate(() => window.fixture.counts())).toEqual({ observers: 1, subscriptions: 1, rows: 1 });
  await page.getByRole('button', { name: 'Invalid query' }).click();
  await expect(page.locator('output')).toHaveText('Query failed');
  expect(await page.evaluate(() => window.fixture.counts())).toEqual({ observers: 0, subscriptions: 0, rows: 1 });
  await page.getByRole('button', { name: 'Invalid query' }).click();
  await expect(page.locator('output')).toHaveText('Browser task');
  await page.getByRole('button', { name: 'Filter' }).click();
  await expect(page.locator('output')).toHaveText('Empty');
  expect(await page.evaluate(() => window.fixture.counts())).toEqual({ observers: 1, subscriptions: 1, rows: 1 });
  await page.evaluate(() => window.fixture.unmount());
  await expect.poll(() => page.evaluate(() => window.fixture.counts())).toEqual({ observers: 0, subscriptions: 0, rows: 1 });
  await page.evaluate(() => window.fixture.mount());
  await expect(page.locator('output')).toHaveText('Browser task');
  await page.evaluate(() => window.fixture.close());
  await page.reload();
  await page.evaluate(config => window.fixture.start(config), config);
  await expect(page.locator('output')).toHaveText('Empty');
  await page.evaluate(() => window.fixture.close());
});
