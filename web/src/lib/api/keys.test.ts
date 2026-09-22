import { describe, expect, it } from "vitest";

import { ROLE_SCOPES } from "./scopes";
import { ApiError } from "./errors";
import { authenticate, parseApiKeys, requireScope } from "./keys";

const ownerSecret = "owner-secret-0123456789abcdef";
const agentSecret = "agent-secret-0123456789abcdef";
const keys = JSON.stringify([
  { name: "iphone", secret: ownerSecret, role: "owner" },
  { name: "chatgpt", secret: agentSecret, role: "agent" },
]);

function request(token?: string): Request {
  return new Request("https://example.test/api/v1/agent/entries", {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
}

function errorCode(run: () => unknown): string | undefined {
  try {
    run();
  } catch (error) {
    return error instanceof ApiError ? error.code : "NOT_API_ERROR";
  }
  return undefined;
}

describe("parseApiKeys", () => {
  it("expands roles into scopes", () => {
    const [owner, agent] = parseApiKeys(keys);
    expect(owner?.scopes).toContain("journey:entries:write");
    expect(agent?.scopes).toEqual(["journey:entries:read", "journey:proposals:write"]);
  });

  /** Comments are private correspondence between the owner and a reader. */
  it("keeps every agent role away from readers' comments", () => {
    for (const role of ["agent", "agent-read"] as const) {
      const scopes = ROLE_SCOPES[role] as readonly string[];
      expect(scopes).not.toContain("journey:comments:manage");
    }
    expect(ROLE_SCOPES.owner).toContain("journey:comments:manage");
  });

  it("treats a missing or blank variable as no keys", () => {
    expect(parseApiKeys(undefined)).toEqual([]);
    expect(parseApiKeys("  ")).toEqual([]);
  });

  it("rejects short secrets, unknown roles and duplicate names", () => {
    expect(errorCode(() => parseApiKeys('[{"name":"a","secret":"short","role":"owner"}]'))).toBe(
      "API_KEYS_INVALID",
    );
    expect(
      errorCode(() => parseApiKeys(JSON.stringify([{ name: "a", secret: ownerSecret, role: "admin" }]))),
    ).toBe("API_KEYS_INVALID");
    expect(
      errorCode(() =>
        parseApiKeys(
          JSON.stringify([
            { name: "a", secret: ownerSecret, role: "owner" },
            { name: "a", secret: agentSecret, role: "agent" },
          ]),
        ),
      ),
    ).toBe("API_KEYS_INVALID");
    expect(errorCode(() => parseApiKeys("not json"))).toBe("API_KEYS_INVALID");
  });
});

describe("authenticate", () => {
  it("identifies the key behind a Bearer token", () => {
    expect(authenticate(request(agentSecret), keys).name).toBe("chatgpt");
  });

  it("rejects missing, wrong and unconfigured tokens", () => {
    expect(errorCode(() => authenticate(request(), keys))).toBe("UNAUTHENTICATED");
    expect(errorCode(() => authenticate(request("wrong-token-0123456789abcdef"), keys))).toBe(
      "UNAUTHENTICATED",
    );
    expect(errorCode(() => authenticate(request(agentSecret), undefined))).toBe("UNAUTHENTICATED");
  });

  it("never lets the agent publish, manage invites or decide proposals", () => {
    const agent = authenticate(request(agentSecret), keys);
    expect(errorCode(() => requireScope(agent, "journey:entries:write"))).toBe("PERMISSION_DENIED");
    expect(errorCode(() => requireScope(agent, "journey:invites:manage"))).toBe("PERMISSION_DENIED");
    expect(errorCode(() => requireScope(agent, "journey:proposals:decide"))).toBe("PERMISSION_DENIED");
    expect(errorCode(() => requireScope(agent, "journey:proposals:write"))).toBeUndefined();
  });
});
