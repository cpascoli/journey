import { NextResponse } from "next/server";

/**
 * The address readers should use, for links the site hands out.
 *
 * `new URL(request.url).origin` cannot be trusted here: behind Netlify's
 * Next.js runtime it reflected the branch-deploy hostname
 * (`main--<site>.netlify.app`), so invite links were minted on a host that is
 * not the site's real domain.
 *
 * `JOURNEY_PUBLIC_ORIGIN` wins when set, which makes links deterministic
 * whichever hostname a request happened to arrive on — including the
 * `.netlify.app` names, which keep answering. Otherwise the forwarded host is
 * what the client actually asked for, and is right for local development too.
 */
export function publicOrigin(
  headers: Headers,
  fallbackUrl: string,
  env: Record<string, string | undefined> = process.env,
): string {
  const configured = env.JOURNEY_PUBLIC_ORIGIN?.trim();
  if (configured) {
    try {
      const url = new URL(configured);
      if (url.protocol === "https:" || url.hostname === "localhost" || url.hostname === "127.0.0.1") {
        return url.origin;
      }
    } catch {
      // A malformed value must not take the site's links down.
    }
  }

  const host = headers.get("x-forwarded-host") ?? headers.get("host");
  if (host) {
    const protocol = headers.get("x-forwarded-proto") ?? "https";
    return `${protocol}://${host}`;
  }
  return new URL(fallbackUrl).origin;
}

/**
 * A redirect to a path on whichever host the browser is already on.
 *
 * The `Location` is relative, so the browser resolves it against the address
 * in its own bar. Building it from `request.url` instead sent readers to the
 * deploy's own `.netlify.app` hostname: the invitation cookie, set on the real
 * domain, did not travel with them, and the journal said the invitation was
 * unavailable. `path` must already be a path on this site.
 */
export function redirectHere(path: string): NextResponse {
  return new NextResponse(null, { status: 303, headers: { Location: path } });
}
