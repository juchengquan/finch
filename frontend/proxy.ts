import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { CONFIGURED_BASE_PATH } from '@/lib/base-path';
import { allowedHostsFromEnv, checkApiRequest } from '@/lib/api-guard';

const isDev = process.env.NODE_ENV === 'development';
const allowedHosts = allowedHostsFromEnv(process.env.FINCH_ALLOWED_HOSTS);

// Runs on every request, dev and production. Two jobs:
//  1. Refuse /api requests from other web pages (CSRF, DNS rebinding) — see
//     lib/api-guard.ts. Runs in dev too: `next dev` is just as reachable.
//  2. Production only: Tailscale Serve strips the /finch mount path before
//     forwarding, so put the base path back for routing.
//
// It must keep running on /api (job 2 rewrites the API calls too), so the
// request-body buffer it implies is sized in next.config.ts
// (proxyClientMaxBodySize) to fit the largest upload the routes accept.
export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const rejected = checkApiRequest({
    method: request.method,
    pathname,
    headers: request.headers,
    basePath: isDev ? '' : CONFIGURED_BASE_PATH,
    allowedHosts,
  });
  if (rejected) return NextResponse.json({ error: rejected.error }, { status: rejected.status });

  if (isDev) return NextResponse.next();
  if (pathname.startsWith(CONFIGURED_BASE_PATH)) return NextResponse.next();

  const dest = CONFIGURED_BASE_PATH + (pathname === '/' ? '' : pathname);
  return NextResponse.rewrite(new URL(dest, request.url));
}
