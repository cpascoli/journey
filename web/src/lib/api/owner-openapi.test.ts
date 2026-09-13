import { existsSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { ownerOpenApiDocument } from "./owner-openapi";

const appDir = path.resolve(__dirname, "../../app");

/** /api/v1/owner/entries/{id} → src/app/api/v1/owner/entries/[id]/route.ts */
function routeFile(apiPath: string): string {
  return path.join(appDir, apiPath.replace(/\{(\w+)\}/g, "[$1]"), "route.ts");
}

describe("owner OpenAPI document", () => {
  const doc = ownerOpenApiDocument("https://example.test");

  it("is OpenAPI 3.1 with bearer auth on every operation", () => {
    expect(doc.openapi).toBe("3.1.0");
    for (const item of Object.values(doc.paths)) {
      for (const operation of Object.values(item)) {
        expect(operation.security).toEqual([{ bearerAuth: [] }]);
        expect(operation.operationId).toMatch(/^[a-z][A-Za-z]+$/);
      }
    }
  });

  it("uses each operationId once", () => {
    const ids = Object.values(doc.paths).flatMap((item) => Object.values(item).map((op) => op.operationId));
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("describes only routes that exist, with a handler for every documented method", async () => {
    for (const [apiPath, item] of Object.entries(doc.paths)) {
      const file = routeFile(apiPath);
      expect(existsSync(file), `${apiPath} → ${file}`).toBe(true);
      const handlers = (await import(file)) as Record<string, unknown>;
      for (const method of Object.keys(item)) {
        expect(typeof handlers[method.toUpperCase()], `${method.toUpperCase()} ${apiPath}`).toBe("function");
      }
    }
  });
});
