import { createHmac, timingSafeEqual } from "node:crypto";

import { apiKeyFingerprint, parseApiKeys } from "@/lib/api/keys";

export const OWNER_COOKIE = "__Host-journey-owner";
export const INVITE_COOKIE = "__Host-journey-invite";
export const SESSION_MAX_AGE = 60 * 60 * 12;

type OwnerSession = {
  name: string;
  fingerprint: string;
  expiresAt: number;
};

function sessionSecret(raw = process.env.JOURNEY_SESSION_SECRET): string {
  if (!raw || raw.length < 32) throw new Error("JOURNEY_SESSION_SECRET must be at least 32 characters.");
  return raw;
}

function signature(payload: string, secret: string): string {
  return createHmac("sha256", secret).update(payload).digest("base64url");
}

export function createOwnerSession(
  name: string,
  keySecret: string,
  now = Date.now(),
  secret = sessionSecret(),
): string {
  const value: OwnerSession = {
    name,
    fingerprint: apiKeyFingerprint(keySecret),
    expiresAt: Math.floor(now / 1000) + SESSION_MAX_AGE,
  };
  const payload = Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${payload}.${signature(payload, secret)}`;
}

export function readOwnerSession(
  value: string | undefined,
  rawKeys = process.env.JOURNEY_API_KEYS,
  now = Date.now(),
  secret = sessionSecret(),
): { name: string } | null {
  if (!value) return null;
  const [payload, suppliedSignature, extra] = value.split(".");
  if (!payload || !suppliedSignature || extra) return null;
  const expected = signature(payload, secret);
  const supplied = Buffer.from(suppliedSignature);
  const expectedBytes = Buffer.from(expected);
  if (supplied.length !== expectedBytes.length || !timingSafeEqual(supplied, expectedBytes)) return null;

  let session: OwnerSession;
  try {
    session = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as OwnerSession;
  } catch {
    return null;
  }
  if (
    typeof session.name !== "string" ||
    typeof session.fingerprint !== "string" ||
    typeof session.expiresAt !== "number" ||
    session.expiresAt <= Math.floor(now / 1000)
  ) {
    return null;
  }
  const key = parseApiKeys(rawKeys).find((candidate) => candidate.name === session.name);
  if (
    !key ||
    !key.scopes.includes("journey:invites:manage") ||
    !key.scopes.includes("journey:entries:read")
  ) {
    return null;
  }
  const current = Buffer.from(apiKeyFingerprint(key.secret));
  const recorded = Buffer.from(session.fingerprint);
  if (current.length !== recorded.length || !timingSafeEqual(current, recorded)) return null;
  return { name: key.name };
}

export function secureCookieOptions(sameSite: "lax" | "strict", maxAge = SESSION_MAX_AGE) {
  return {
    httpOnly: true,
    secure: true,
    sameSite,
    path: "/",
    maxAge,
  } as const;
}

