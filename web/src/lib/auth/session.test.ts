import { describe, expect, it } from "vitest";

import { createOwnerSession, readOwnerSession } from "./session";

const sessionSecret = "s".repeat(32);
const ownerSecret = "owner-secret-that-is-long-enough";
const keys = JSON.stringify([{ name: "owner", secret: ownerSecret, role: "owner" }]);

describe("owner sessions", () => {
  it("contains no raw owner key and revalidates the configured fingerprint", () => {
    const session = createOwnerSession("owner", ownerSecret, 1_000, sessionSecret);
    expect(session).not.toContain(ownerSecret);
    expect(readOwnerSession(session, keys, 1_000, sessionSecret)).toEqual({ name: "owner" });
  });

  it("is invalid after key rotation", () => {
    const session = createOwnerSession("owner", ownerSecret, 1_000, sessionSecret);
    const rotated = JSON.stringify([{ name: "owner", secret: "rotated-owner-secret-long-enough", role: "owner" }]);
    expect(readOwnerSession(session, rotated, 1_000, sessionSecret)).toBeNull();
  });

  it("rejects tampering, expiry, and non-owner keys", () => {
    const session = createOwnerSession("owner", ownerSecret, 1_000, sessionSecret);
    expect(readOwnerSession(`${session}x`, keys, 1_000, sessionSecret)).toBeNull();
    expect(readOwnerSession(session, keys, 1_000 + 13 * 60 * 60 * 1_000, sessionSecret)).toBeNull();
    const agentKeys = JSON.stringify([{ name: "owner", secret: ownerSecret, role: "agent" }]);
    expect(readOwnerSession(session, agentKeys, 1_000, sessionSecret)).toBeNull();
  });

  it("revalidates that the current key can still read entries", () => {
    const session = createOwnerSession("owner", ownerSecret, 1_000, sessionSecret);
    const inviteOnly = JSON.stringify([{
      name: "owner",
      secret: ownerSecret,
      scopes: ["journey:invites:manage"],
    }]);
    expect(readOwnerSession(session, inviteOnly, 1_000, sessionSecret)).toBeNull();
  });
});

