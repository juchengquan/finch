import type { NextConfig } from "next";

const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH || '/finch';
const isDev = process.env.NODE_ENV === 'development';

const nextConfig: NextConfig = {
  serverExternalPackages: ['@sqlite.org/sqlite-wasm'],
  allowedDevOrigins: ['192.168.50.*', '*.local', 'blackmount8s-mac-mini.tailfc8710.ts.net'],
  basePath: isDev ? '' : BASE_PATH,
};

export default nextConfig;
