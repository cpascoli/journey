import { ApiError, validationError } from "./errors";
import { authenticate, requireScope, type ApiPrincipal } from "./keys";
import type { ApiScope } from "./scopes";

export const MAX_JSON_BYTES = 256 * 1024;

export type ApiContext = {
  request: Request;
  principal: ApiPrincipal;
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

export function errorResponse(error: ApiError): Response {
  return jsonResponse(
    { error: { code: error.code, message: error.message, ...error.details } },
    error.status,
  );
}

/** Authenticates, checks the scope, and turns thrown ApiErrors into JSON error responses. */
export async function handleApiRequest(
  request: Request,
  scope: ApiScope,
  handler: (ctx: ApiContext) => Promise<Response>,
): Promise<Response> {
  try {
    const principal = authenticate(request);
    requireScope(principal, scope);
    return await handler({ request, principal });
  } catch (error) {
    if (error instanceof ApiError) return errorResponse(error);
    // Logged, not echoed: unexpected messages can carry internals.
    console.error("Unhandled API error", error);
    return errorResponse(new ApiError(500, "INTERNAL_ERROR", "Something went wrong on the server."));
  }
}

function tooLarge(maxBytes: number): ApiError {
  return new ApiError(413, "PAYLOAD_TOO_LARGE", `Request body must be at most ${maxBytes} bytes.`);
}

export async function readBytes(request: Request, maxBytes: number): Promise<Uint8Array> {
  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) throw tooLarge(maxBytes);
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > maxBytes) throw tooLarge(maxBytes);
  return bytes;
}

export async function readJson(request: Request, maxBytes = MAX_JSON_BYTES): Promise<unknown> {
  const text = new TextDecoder().decode(await readBytes(request, maxBytes));
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw validationError("Body must be valid JSON.");
  }
}
