import { test, expect } from 'bun:test';
import { resolveServerLocale, resolveClientLocale, matchBrowserLocale } from './i18n-provider';

// Regression guard for the 账户-vs-Accounts hydration mismatch.
//
// The bug: browser detection was run inline during render, so the client's
// hydration pass computed a different locale (zh-CN) than the server HTML (en).
// The fix routes detection through useSyncExternalStore's CLIENT snapshot only;
// the SERVER snapshot (used for SSR *and* the hydration render) must always be
// the default and must never consult the browser.

test('server locale is always the default and structurally ignores the browser', () => {
  // No browser input by signature → it cannot drift from the SSR HTML.
  expect(resolveServerLocale()).toBe('en');
});

test('matchBrowserLocale: exact tag, language-only fallback, and misses', () => {
  expect(matchBrowserLocale(['zh-CN', 'en'])).toBe('zh-CN'); // exact tag
  expect(matchBrowserLocale(['zh'])).toBe('zh-CN'); // language-only zh -> zh-CN
  expect(matchBrowserLocale(['en-GB'])).toBe('en'); // en-GB -> en
  expect(matchBrowserLocale(['fr-FR', 'de'])).toBeNull(); // unsupported
  expect(matchBrowserLocale([])).toBeNull();
});

test('client locale prefers persisted, then detected browser locale, then default', () => {
  expect(resolveClientLocale('zh-CN', ['en'])).toBe('zh-CN'); // persisted wins over browser
  expect(resolveClientLocale(null, ['zh-CN'])).toBe('zh-CN'); // falls back to detected
  expect(resolveClientLocale(null, ['fr-FR'])).toBe('en'); // nothing matches -> default
  expect(resolveClientLocale(null, [])).toBe('en');
});
