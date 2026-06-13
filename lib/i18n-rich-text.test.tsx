import { test, expect } from 'bun:test';
import { createTranslator } from 'use-intl';
import { renderToStaticMarkup } from 'react-dom/server';
import en from '@/messages/en.json';
import zhCN from '@/messages/zh-CN.json';

// Guards every t.rich(...) call site that passes a FUNCTION value: that value
// must be referenced as a TAG (<x>…</x>) in the message, NOT a placeholder
// ({x}). next-intl/use-intl placeholders only accept string | number | Date —
// a function handed to a {placeholder} is treated as a React child, which
// React 19 logs as "Functions are not valid as a React child" and then DROPS
// (it never calls the handler). So the regression check is positive: render the
// real message with a marker-emitting handler and assert the marker survives.
// Before the fix (placeholder) the marker is absent; after (tag) it appears.

interface Site {
  ns: string;
  key: string;
  /** keys whose value is a tag handler (must be `<key>` in the message) */
  fns: string[];
  /** keys whose value is a plain string placeholder (stay `{key}`) */
  strs?: Record<string, string>;
}

// Mirror of the live call sites (handler bodies reduced to a unique marker;
// only the message↔value SHAPE matters, not what the element renders).
const SITES: Site[] = [
  { ns: 'scheduled', key: 'incoming', fns: ['amount'] },
  { ns: 'budgets', key: 'empty.title', fns: ['ledger'], strs: { type: 'Spending' } },
  { ns: 'accounts', key: 'empty.title', fns: ['ledger'] },
  { ns: 'rules', key: 'intro', fns: ['ledger'] },
  { ns: 'txnDetail', key: 'ruleSuggestion.prompt', fns: ['merchant', 'category'] },
  // Already correct before this fix — included so the test guards every
  // tag-bearing message (a sweep confirmed these are the only 6 across both locales).
  { ns: 'accountForecast', key: 'addTemplate', fns: ['link'] },
];

const LOCALES: Array<[string, Record<string, unknown>]> = [
  ['en', en as Record<string, unknown>],
  ['zh-CN', zhCN as Record<string, unknown>],
];

const marker = (name: string) => `«${name}»`;

for (const [locale, messages] of LOCALES) {
  for (const site of SITES) {
    test(`t.rich(${site.ns}.${site.key}) renders each tag handler [${locale}]`, () => {
      const values: Record<string, string | (() => React.ReactNode)> = { ...(site.strs ?? {}) };
      for (const name of site.fns) values[name] = () => <i>{marker(name)}</i>;

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const t = createTranslator({ locale, messages, namespace: site.ns } as any);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const html = renderToStaticMarkup(<>{t.rich(site.key as any, values as any)}</>);

      // Each function handler must have been invoked as a tag — its marker
      // survives in the output. A function leaked into a {placeholder} is
      // dropped by React, so its marker would be missing.
      for (const name of site.fns) expect(html).toContain(marker(name));
      // String placeholders interpolate as-is.
      for (const v of Object.values(site.strs ?? {})) expect(html).toContain(v);
    });
  }
}
