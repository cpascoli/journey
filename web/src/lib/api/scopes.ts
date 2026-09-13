export const API_SCOPES = [
  "journey:entries:read",
  "journey:entries:write",
  "journey:invites:manage",
  "journey:proposals:write",
  "journey:proposals:decide",
] as const;

export type ApiScope = (typeof API_SCOPES)[number];

/**
 * `owner` is the iPhone app. `agent` is the ChatGPT GPT: it reads entries and
 * proposes story text, and must never publish, delete or decide on its own
 * proposals, so it gets no write, invite or decide scope.
 */
export const ROLE_SCOPES = {
  owner: [...API_SCOPES],
  agent: ["journey:entries:read", "journey:proposals:write"],
  "agent-read": ["journey:entries:read"],
} as const satisfies Record<string, readonly ApiScope[]>;

export type ApiRole = keyof typeof ROLE_SCOPES;

const SCOPE_SET = new Set<string>(API_SCOPES);

export function isApiScope(value: string): value is ApiScope {
  return SCOPE_SET.has(value);
}

export function isApiRole(value: unknown): value is ApiRole {
  return typeof value === "string" && Object.hasOwn(ROLE_SCOPES, value);
}
