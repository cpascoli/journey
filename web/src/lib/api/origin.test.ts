import { describe, expect, it } from "vitest";

import { publicOrigin, redirectHere } from "./origin";

const request = "https://main--journey-web.netlify.app/api/v1/owner/invites";

function headers(values: Record<string, string> = {}): Headers {
  return new Headers(values);
}

describe("publicOrigin", () => {
  /**
   * The bug this exists for: behind Netlify's runtime the request URL carried
   * the branch-deploy hostname, so invite links pointed at it.
   */
  it("prefers the configured public origin over the request's own host", () => {
    expect(
      publicOrigin(headers({ host: "main--journey-web.netlify.app" }), request, {
        JOURNEY_PUBLIC_ORIGIN: "https://ashone.me",
      }),
    ).toBe("https://ashone.me");
  });

  it("ignores a trailing path or slash on the configured value", () => {
    expect(publicOrigin(headers(), request, { JOURNEY_PUBLIC_ORIGIN: "https://ashone.me/" }))
      .toBe("https://ashone.me");
  });

  it("falls back to the forwarded host when nothing is configured", () => {
    expect(
      publicOrigin(headers({ "x-forwarded-host": "ashone.me", "x-forwarded-proto": "https" }), request, {}),
    ).toBe("https://ashone.me");
  });

  it("uses the plain host header when there is no forwarded one", () => {
    expect(publicOrigin(headers({ host: "ashone.me" }), request, {})).toBe("https://ashone.me");
  });

  it("keeps http for local development", () => {
    expect(
      publicOrigin(headers({ host: "127.0.0.1:3000", "x-forwarded-proto": "http" }), request, {}),
    ).toBe("http://127.0.0.1:3000");
    expect(publicOrigin(headers(), request, { JOURNEY_PUBLIC_ORIGIN: "http://localhost:3000" }))
      .toBe("http://localhost:3000");
  });

  /** A link is public, so an http origin must not be honoured in production. */
  it("refuses an insecure configured origin that is not local", () => {
    expect(
      publicOrigin(headers({ host: "ashone.me" }), request, {
        JOURNEY_PUBLIC_ORIGIN: "http://evil.example.com",
      }),
    ).toBe("https://ashone.me");
  });

  it("survives a malformed configured value rather than failing", () => {
    expect(publicOrigin(headers({ host: "ashone.me" }), request, { JOURNEY_PUBLIC_ORIGIN: "not a url" }))
      .toBe("https://ashone.me");
  });

  it("uses the request as a last resort", () => {
    expect(publicOrigin(headers(), request, {})).toBe("https://main--journey-web.netlify.app");
  });
});

describe("redirectHere", () => {
  /** Absolute, it carried the deploy's hostname and lost the invitation cookie. */
  it("sends a relative location, so the browser stays on its own host", () => {
    const response = redirectHere("/read");
    expect(response.status).toBe(303);
    expect(response.headers.get("location")).toBe("/read");
  });

  it("keeps the cookies set on it", () => {
    const response = redirectHere("/read");
    response.cookies.set("journey_invite", "token", { path: "/" });
    expect(response.headers.get("set-cookie")).toContain("journey_invite=token");
  });
});
