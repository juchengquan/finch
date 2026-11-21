import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';
import { CONFIGURED_BASE_PATH } from '@/lib/base-path';

// Only needed in production — dev mode uses localhost directly.
const isDev = process.env.NODE_ENV === 'development';

// Tailscale Serve strips the /finch mount path before forwarding, so put the
// base path back for routing. It must keep running on /api (the API calls are
// rewritten too), so the request-body buffer it implies is sized in
// next.config.ts (proxyClientMaxBodySize) to fit the largest upload the routes
// accept.
export function proxy(request: NextRequest) {
  if (isDev) return NextResponse.next();

  const { pathname } = request.nextUrl;

  if (pathname.startsWith(CONFIGURED_BASE_PATH)) return NextResponse.next();

  const dest = CONFIGURED_BASE_PATH + (pathname === '/' ? '' : pathname);
  return NextResponse.rewrite(new URL(dest, request.url));
}
