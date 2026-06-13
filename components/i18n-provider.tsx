'use client';

// I18nProvider — per-device locale + ICU plurals on top of next-intl.
//
// Locale persistence mirrors the active-ledger pattern (PR #109,
// `components/ledger-provider.tsx`): useSyncExternalStore for SSR
// safety, cross-tab updates via the `storage` event, manual dispatch
// in the writer so same-tab subscribers re-read immediately.
//
// Server snapshot returns null so the SSR HTML uses the default (en).
// On the client, `navigator.languages` is matched against the
// supported set; on a hit, the provider re-renders with the matched
// locale. First-time visitors with a Chinese browser see Chinese
// without ceremony.

import { NextIntlClientProvider } from 'next-intl';
import { useCallback, useSyncExternalStore, type ReactNode } from 'react';
import enMessages from '@/messages/en.json';
import zhCNMessages from '@/messages/zh-CN.json';

type Messages = typeof enMessages;
type Locale = 'en' | 'zh-CN';

const SUPPORTED: Locale[] = ['en', 'zh-CN'];
const DEFAULT: Locale = 'en';
const LOCALE_KEY = 'finch.locale';

const MESSAGES: Record<Locale, Messages> = {
  en: enMessages,
  'zh-CN': zhCNMessages as Messages,
};

/** Native-language label for the Settings dropdown. Hardcoded so the row
 *  reads naturally even when the user is in the "other" UI. */
export const LOCALE_LABELS: Record<Locale, string> = {
  en: 'English',
  'zh-CN': '中文(简体)',
};

export type { Locale };
export const SUPPORTED_LOCALES = SUPPORTED;

function isSupported(v: string | null | undefined): v is Locale {
  return !!v && (SUPPORTED as string[]).includes(v);
}

function readPersistedLocale(): Locale | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = window.localStorage.getItem(LOCALE_KEY);
    return isSupported(raw) ? raw : null;
  } catch {
    return null;
  }
}

function writePersistedLocale(locale: Locale): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(LOCALE_KEY, locale);
  } catch {
    /* localStorage unavailable / quota — fall back to no-op */
  }
  // Same-tab subscribers — the storage event only fires across tabs.
  window.dispatchEvent(new StorageEvent('storage', { key: LOCALE_KEY }));
}

function subscribePersistedLocale(cb: () => void): () => void {
  if (typeof window === 'undefined') return () => undefined;
  const onStorage = (e: StorageEvent) => {
    if (e.key === LOCALE_KEY) cb();
  };
  window.addEventListener('storage', onStorage);
  return () => window.removeEventListener('storage', onStorage);
}

/** Pure browser-locale matcher: exact tag first (zh-CN), then the
 *  language-only tag (zh -> zh-CN, en-GB -> en). Returns null when nothing
 *  matches. Exported for tests; the runtime caller passes navigator.languages. */
export function matchBrowserLocale(langs: readonly string[]): Locale | null {
  for (const tag of langs) {
    if (isSupported(tag)) return tag;
    const short = tag.split('-')[0];
    const hit = SUPPORTED.find((s) => s.split('-')[0] === short);
    if (hit) return hit;
  }
  return null;
}

/** navigator.languages, normalised to a plain array (empty on the server). */
function navigatorLangs(): string[] {
  if (typeof navigator === 'undefined') return [];
  return [...(navigator.languages ?? (navigator.language ? [navigator.language] : []))];
}

/** SSR + hydration snapshot. ALWAYS the default locale — it never consults the
 *  browser, so the client's hydration render matches the server HTML. Browser
 *  detection is deferred to the post-hydration client snapshot below; folding
 *  it in here (or computing it inline during render) is what caused the
 *  账户-vs-Accounts hydration mismatch. */
export function resolveServerLocale(): Locale {
  return DEFAULT;
}

/** Post-hydration client snapshot: persisted choice > detected browser locale >
 *  default. Pure (takes persisted + browser languages) so the decision is
 *  unit-testable without a DOM. */
export function resolveClientLocale(persisted: Locale | null, langs: readonly string[]): Locale {
  return persisted ?? matchBrowserLocale(langs) ?? DEFAULT;
}

interface I18nContextValue {
  locale: Locale;
  setLocale: (locale: Locale) => void;
}

import { createContext, useContext } from 'react';

const I18nContext = createContext<I18nContextValue | null>(null);

/** Wraps the tree with NextIntlClientProvider + a small context that
 *  exposes the active locale + a setter. Drop in at app/layout.tsx. */
export function I18nProvider({ children }: { children: ReactNode }) {
  // Locale flows entirely through useSyncExternalStore so its hydration
  // contract holds: the SERVER snapshot (resolveServerLocale = default) is used
  // for SSR *and* the client's hydration render, so they always match; the
  // CLIENT snapshot (persisted > detected browser locale > default) applies
  // only on the post-hydration commit. Detecting the browser inline during
  // render — as this used to — broke that contract (账户-vs-Accounts mismatch).
  const locale = useSyncExternalStore(
    subscribePersistedLocale,
    () => resolveClientLocale(readPersistedLocale(), navigatorLangs()),
    resolveServerLocale,
  );

  const setLocale = useCallback((next: Locale) => {
    writePersistedLocale(next);
  }, []);

  const messages = MESSAGES[locale] ?? MESSAGES[DEFAULT];

  return (
    <I18nContext.Provider value={{ locale, setLocale }}>
      <NextIntlClientProvider locale={locale} messages={messages}>
        {children}
      </NextIntlClientProvider>
    </I18nContext.Provider>
  );
}

/** Read the active locale + write to it. Use `useTranslations` from
 *  next-intl for the actual translation function. */
export function useAppLocale(): I18nContextValue {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error('useAppLocale must be used within I18nProvider');
  return ctx;
}
