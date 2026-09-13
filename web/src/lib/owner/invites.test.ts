import { describe, expect, it } from "vitest";

import { hashInviteToken, inviteUrl, newInviteToken } from "./invites";

describe("invite tokens", () => {
  it("are long, URL-safe and unique", () => {
    const tokens = new Set(Array.from({ length: 50 }, newInviteToken));
    expect(tokens.size).toBe(50);
    for (const token of tokens) expect(token).toMatch(/^[A-Za-z0-9_-]{32}$/);
  });

  it("are stored only as a stable hash that differs from the token", () => {
    const token = newInviteToken();
    expect(hashInviteToken(token)).toBe(hashInviteToken(token));
    expect(hashInviteToken(token)).toMatch(/^[0-9a-f]{64}$/);
    expect(hashInviteToken(token)).not.toContain(token);
  });

  it("build the reading link", () => {
    expect(inviteUrl("https://journey-web.netlify.app", "abc")).toBe("https://journey-web.netlify.app/i/abc");
  });
});
