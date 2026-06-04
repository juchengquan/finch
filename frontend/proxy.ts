import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

// Only needed in production — dev mode uses localhost directly.
const isDev = process.env.NODE_ENV === 'development';

const BASE = '/finch';

export function proxy(request: NextRequest) {
  if (isDev) return NextResponse.next();

  const { pathname } = request.nextUrl;

  if (pathname.startsWith(BASE)) return NextResponse.next();

  const dest = BASE + (pathname === '/' ? '' : pathname);
  return NextResponse.rewrite(new URL(dest, request.url));
}
