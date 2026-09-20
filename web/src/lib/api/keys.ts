import { createHash, timingSafeEqual } from "node:crypto";

import { ApiError, permissionDenied, unauthenticated } from "./errors";
import { isApiRole, isApiScope, ROLE_SCOPES, type ApiScope } from "./scopes";

export type ApiPrincipal = {
  name: string;
  scopes: readonly ApiScope[];
};

export type ApiKeyConfig = {
  name: string;
  secret: string;
  scopes: ApiScope[];
};

const ENV_NAME = "JOURNEY_API_KEYS";
const MIN_SECRET_LENGTH = 24;

function configError(message: string): ApiError {
  return new ApiError(500, "API_KEYS_INVALID", message);
}

function parseKeyEntry(value: unknown, index: number): ApiKeyConfig {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw configError(`${ENV_NAME}[${index}] must be an object.`);
  }
  const record = value as Record<string, unknown>;
  const name = typeof record.name === "string" ? record.name.trim() : "";
  const secret = typeof record.secret === "string" ? record.secret : "";
  if (!name) {
    throw configError(`${ENV_NAME}[${index}].name is required.`);
  }
  if (secret.length < MIN_SECRET_LENGTH) {
    throw configError(`${ENV_NAME}[${index}].secret must be at least ${MIN_SECRET_LENGTH} characters.`);
  }

  if (Array.isArray(record.scopes)) {
    const scopes = record.scopes.map((scope) => {
      if (typeof scope !== "string" || !isApiScope(scope)) {
        throw configError(`${ENV_NAME}[${index}] has an unknown scope.`);
      }
      return scope;
    });
    return { name, secret, scopes };
  }
  if (isApiRole(record.role)) {
    return { name, secret, scopes: [...ROLE_SCOPES[record.role]] };
  }
  throw configError(
    `${ENV_NAME}[${index}] needs a role of "owner", "agent" or "agent-read", or an explicit scopes array.`,
  );
}

export function parseApiKeys(raw: string | undefined): ApiKeyConfig[] {
  if (raw == null || raw.trim().length === 0) return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw configError(`${ENV_NAME} must be valid JSON.`);
  }
  if (!Array.isArray(parsed)) {
    throw configError(`${ENV_NAME} must be a JSON array.`);
  }
  const keys = parsed.map(parseKeyEntry);
  const names = new Set<string>();
  for (const key of keys) {
    if (names.has(key.name)) {
      throw configError(`${ENV_NAME} has two keys named "${key.name}".`);
    }
    names.add(key.name);
  }
  return keys;
}

export function secretsEqual(left: string, right: string): boolean {
  const leftBuf = Buffer.from(left);
  const rightBuf = Buffer.from(right);
  if (leftBuf.length !== rightBuf.length) return false;
  return timingSafeEqual(leftBuf, rightBuf);
}

export function apiKeyFingerprint(secret: string): string {
  return createHash("sha256").update(secret).digest("base64url");
}

export function authenticate(request: Request, rawKeys = process.env[ENV_NAME]): ApiPrincipal {
  const header = request.headers.get("authorization") ?? "";
  const token = /^Bearer\s+(\S+)/i.exec(header)?.[1] ?? "";
  return authenticateToken(token, rawKeys);
}

export function authenticateToken(token: string, rawKeys = process.env[ENV_NAME]): ApiPrincipal {
  if (!token) {
    throw unauthenticated("Missing Authorization: Bearer token.");
  }
  const keys = parseApiKeys(rawKeys);
  if (keys.length === 0) {
    throw unauthenticated("API keys are not configured.");
  }
  const matched = keys.find((key) => secretsEqual(key.secret, token));
  if (!matched) {
    throw unauthenticated("Invalid API token.");
  }
  return { name: matched.name, scopes: matched.scopes };
}

export function requireScope(principal: ApiPrincipal, scope: ApiScope): void {
  if (!principal.scopes.includes(scope)) {
    throw permissionDenied(scope);
  }
}
