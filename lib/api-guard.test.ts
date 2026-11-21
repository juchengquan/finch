import { describe, expect, test } from 'bun:test';
import { API_REQUEST_HEADER, allowedHostsFromEnv, checkApiRequest, isAllowedHost } from './api-guard';

function req(over: {
  method?: string;
  pathname?: string;
  headers?: Record<string, string>;
  basePath?: string;
  allowedHosts?: string[];
}) {
  const headers = new Headers({ host: 'localhost:3000', ...over.headers });
  return checkApiRequest({
    method: over.method ?? 'POST',
    pathname: over.pathname ?? '/api/mutate',
    headers,
    basePath: over.basePath ?? '',
    allowedHosts: over.allowedHosts,
  });
}

describe('checkApiRequest — cross-site requests', () => {
  test('a POST without the header is refused (what a cross-site form or no-cors fetch sends)', () => {
    expect(req({})?.status).toBe(403);
  });

  test('a POST with the header goes through', () => {
    expect(req({ headers: { [API_REQUEST_HEADER]: '1' } })).toBeNull();
  });

  test('DELETE / PUT / PATCH need the header too', () => {
    for (const method of ['DELETE', 'PUT', 'PATCH', 'post']) {
      expect(req({ method })?.status).toBe(403);
    }
  });

  test('GET and HEAD need no header (the browser loads attachments with <img src>)', () => {
    expect(req({ method: 'GET', pathname: '/api/state' })).toBeNull();
    expect(req({ method: 'HEAD', pathname: '/api/attachments/x' })).toBeNull();
  });

  test('the check finds /api under the base path, and only there', () => {
    expect(req({ pathname: '/finch/api/mutate', basePath: '/finch' })?.status).toBe(403);
    expect(req({ pathname: '/api/mutate', basePath: '/finch' })?.status).toBe(403); // prefix stripped by Tailscale
    expect(req({ pathname: '/finch/accounts', basePath: '/finch' })).toBeNull();
    expect(req({ pathname: '/apix/mutate' })).toBeNull();
  });
});

describe('checkApiRequest — DNS rebinding', () => {
  test('a request whose Host is someone else\'s domain is refused, even a GET', () => {
    const r = req({ method: 'GET', pathname: '/api/export', headers: { host: 'attacker.example:3000' } });
    expect(r?.status).toBe(403);
    expect(r?.error).toMatch(/FINCH_ALLOWED_HOSTS/);
  });

  test('FINCH_ALLOWED_HOSTS lets a named host through', () => {
    const allowedHosts = allowedHostsFromEnv(' finch.example.com , .home.arpa ');
    expect(req({ method: 'GET', pathname: '/api/state', headers: { host: 'finch.example.com' }, allowedHosts })).toBeNull();
  });
});

describe('isAllowedHost', () => {
  test.each([
    'localhost:3000',
    'localhost',
    'app.localhost',
    '127.0.0.1:3001',
    '192.168.50.20:3000',
    '[::1]:3000',
    'blackmount8s-mac-mini',
    'mac-mini.local',
    'host.tailfc8710.ts.net',
    'LOCALHOST:3000',
    'host.tailfc8710.ts.net.',
  ])('allows %s', (host) => {
    expect(isAllowedHost(host)).toBe(true);
  });

  test.each(['attacker.example', 'evil.com:3000', 'ts.net.evil.com', 'local.evil.com', '127.0.0.1.nip.io'])(
    'refuses %s',
    (host) => {
      expect(isAllowedHost(host)).toBe(false);
    },
  );

  test('extra entries match exactly, or as a suffix with a leading dot', () => {
    expect(isAllowedHost('finch.example.com', ['finch.example.com'])).toBe(true);
    expect(isAllowedHost('other.example.com', ['finch.example.com'])).toBe(false);
    expect(isAllowedHost('nas.home.arpa:8080', ['.home.arpa'])).toBe(true);
    expect(isAllowedHost('home.arpa.evil.com', ['.home.arpa'])).toBe(false);
  });

  test('a missing Host header is not a browser, so it is not refused', () => {
    expect(isAllowedHost(null)).toBe(true);
  });
});
