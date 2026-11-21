// Request checks for /api/*, run by proxy.ts before any route handler.
//
// The app has no login: it's meant to be reached only by its owner (on this
// machine, or through Tailscale Serve). Two checks keep other web pages from
// using the owner's browser to reach it:
//
// 1. Cross-site request forgery. Any page the owner visits can send a POST to
//    localhost — `fetch(url, {method:'POST', mode:'no-cors', body})` with a
//    text/plain body needs no CORS preflight, and the routes parse it as JSON
//    anyway. So a state-changing request must carry API_REQUEST_HEADER: a
//    cross-origin page can't add a custom header without a preflight, and the
//    server never approves one.
//
// 2. DNS rebinding. A page on attacker.example can re-point its own name at
//    127.0.0.1 and then make same-origin requests (custom header included) to
//    this server — including GET /api/export, which returns the whole ledger.
//    Such a request still carries `Host: attacker.example`, so /api only
//    answers to hosts that can't be rebound by an outsider: IP literals,
//    localhost, single-label machine names, *.local, *.ts.net, and anything
//    listed in FINCH_ALLOWED_HOSTS.

export const API_REQUEST_HEADER = 'x-finch-request';

const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

export interface ApiRejection {
  status: 403;
  error: string;
}

/** `extra` entries match exactly, or as a suffix when they start with a dot
 *  (".example.com" allows "finch.example.com"). */
export function isAllowedHost(hostHeader: string | null, extra: readonly string[] = []): boolean {
  if (!hostHeader) return true; // browsers always send Host; a missing one isn't a browser
  const host = hostname(hostHeader);
  if (!host) return false;
  if (isIpLiteral(host)) return true;
  if (host === 'localhost' || host.endsWith('.localhost')) return true;
  if (!host.includes('.')) return true; // single-label machine name
  if (host.endsWith('.local') || host.endsWith('.ts.net')) return true;
  return extra.some((e) => {
    const entry = e.trim().toLowerCase();
    if (!entry) return false;
    return entry.startsWith('.') ? host.endsWith(entry) : host === entry;
  });
}

/** Returns why the request is refused, or null to let it through. `pathname`
 *  is the path with or without the base path. */
export function checkApiRequest(req: {
  method: string;
  pathname: string;
  headers: { get(name: string): string | null };
  basePath: string;
  allowedHosts?: readonly string[];
}): ApiRejection | null {
  const path = req.basePath && req.pathname.startsWith(`${req.basePath}/`)
    ? req.pathname.slice(req.basePath.length)
    : req.pathname;
  if (!path.startsWith('/api/')) return null;

  if (!isAllowedHost(req.headers.get('host'), req.allowedHosts)) {
    return { status: 403, error: 'Host not allowed. Add it to FINCH_ALLOWED_HOSTS to reach the API through it.' };
  }
  if (!SAFE_METHODS.has(req.method.toUpperCase()) && req.headers.get(API_REQUEST_HEADER) !== '1') {
    return { status: 403, error: `Missing ${API_REQUEST_HEADER} header.` };
  }
  return null;
}

/** FINCH_ALLOWED_HOSTS: comma-separated host names (see isAllowedHost). */
export function allowedHostsFromEnv(value: string | undefined): string[] {
  return (value ?? '').split(',').map((s) => s.trim()).filter(Boolean);
}

function hostname(hostHeader: string): string | null {
  const h = hostHeader.trim().toLowerCase();
  if (h.startsWith('[')) {
    const end = h.indexOf(']');
    return end > 0 ? h.slice(1, end) : null; // [::1]:3000 → ::1
  }
  const colon = h.lastIndexOf(':');
  const name = colon >= 0 && h.indexOf(':') === colon ? h.slice(0, colon) : h;
  return name.replace(/\.$/, '') || null; // a trailing dot names the same host
}

function isIpLiteral(host: string): boolean {
  if (host.includes(':')) return true; // IPv6 (brackets already stripped)
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(host);
}
