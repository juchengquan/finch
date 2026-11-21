import type { NextConfig } from "next";
import { CONFIGURED_BASE_PATH } from "./lib/base-path";

const isDev = process.env.NODE_ENV === 'development';

// proxy.ts runs on /api, so Next buffers each request body for it — and cuts it
// off at 10 MB by default, silently: a 12 MB receipt or .finch import reached
// its route truncated and failed to parse. Size the buffer to the largest body
// the routes accept (their own caps, same env vars), plus multipart overhead.
function uploadCapMb(): number {
  const num = (v: string | undefined, fallback: number) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : fallback;
  };
  const importMb = num(process.env.FINCH_IMPORT_MAX_MB, 50);
  const attachmentMb = num(process.env.FINCH_ATTACHMENT_MAX_BYTES, 50 * 1024 * 1024) / (1024 * 1024);
  return Math.ceil(Math.max(importMb, attachmentMb)) + 5;
}

const nextConfig: NextConfig = {
  allowedDevOrigins: ['192.168.50.*', '*.local', 'blackmount8s-mac-mini.tailfc8710.ts.net'],
  basePath: isDev ? '' : CONFIGURED_BASE_PATH,
  outputFileTracingExcludes: { '/*': ['./next.config.ts'] },
  experimental: {
    proxyClientMaxBodySize: `${uploadCapMb()}mb`,
  },
};

export default nextConfig;
