// The URL prefix the production build is served under (Tailscale Serve mounts
// the app at /finch by default). One definition for next.config.ts, proxy.ts
// and the client fetch helpers, so NEXT_PUBLIC_BASE_PATH changes all of them.
// NEXT_PUBLIC_* is inlined at build time, so a change needs a rebuild.

/** The configured prefix, regardless of mode. */
export const CONFIGURED_BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH || '/finch';

/** The prefix in effect: dev runs bare at localhost:3000 (basePath + Turbopack
 *  dev don't mix), production uses the configured one. */
export const BASE_PATH = process.env.NODE_ENV === 'development' ? '' : CONFIGURED_BASE_PATH;
