import { createHash, randomBytes } from "node:crypto";

/** A new invite token: 192 random bits, URL-safe. Shown once; only its hash is stored. */
export function newInviteToken(): string {
  return randomBytes(24).toString("base64url");
}

export function hashInviteToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function inviteUrl(origin: string, token: string): string {
  return `${origin}/i/${token}`;
}
