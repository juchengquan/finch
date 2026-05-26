import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Dev only: allow real devices on the LAN (e.g. an iPhone hitting
  // http://192.168.50.53:3000) to load the /_next/* JS chunks. Next 16 blocks
  // cross-origin dev requests by default, which leaves the page rendered but
  // un-hydrated — links work, but every onClick button is dead. A bare '*' is
  // not honored here; origins must be listed explicitly (subdomain-style globs).
  allowedDevOrigins: ['192.168.50.*', '*.local'],
};

export default nextConfig;
