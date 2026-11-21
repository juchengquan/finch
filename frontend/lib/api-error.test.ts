import { expect, test } from 'bun:test';
import { errorMessage, errorResponse } from './api-error';
import { I18nError } from './i18n-error';

test('an engine refusal (I18nError) is a 400 that keeps its code; anything else is a 500', async () => {
  const refused = errorResponse(new I18nError('error.unknownAction', { action: 'x' }, 'Unknown action "x"'));
  expect(refused.status).toBe(400);
  expect(await refused.json()).toEqual({
    error: { code: 'error.unknownAction', params: { action: 'x' }, message: 'Unknown action "x"' },
  });

  const fault = errorResponse(new Error('disk full'));
  expect(fault.status).toBe(500);
  expect(await fault.json()).toEqual({ error: { message: 'disk full' } });
});

test('errorMessage sends the same { error: { message } } shape', async () => {
  const r = errorMessage('Missing action', 400);
  expect(r.status).toBe(400);
  expect(await r.json()).toEqual({ error: { message: 'Missing action' } });
});
