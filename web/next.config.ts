import type { NextConfig } from "next";

/**
 * Security headers are set here rather than in netlify.toml: a `[[headers]]`
 * block there does not reach responses served by the Next.js runtime, which is
 * every route on this site, so they were silently absent in production.
 *
 * Netlify already sends Strict-Transport-Security (with `preload`) and
 * X-Content-Type-Options itself; setting them again here would only risk
 * duplicate headers, so these are the three it does not supply.
 */
const securityHeaders = [
  // Entries are private; a referrer must never carry an entry id off-site.
  { key: "Referrer-Policy", value: "no-referrer" },
  // Nothing here is meant to be framed, and framing invites clickjacking of
  // the owner dashboard's forms.
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
