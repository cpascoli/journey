import { jsonResponse } from "@/lib/api/http";
import { ownerOpenApiDocument } from "@/lib/api/owner-openapi";

export const dynamic = "force-dynamic";

/** Public: the contract describes the API, and every operation still needs the owner key. */
export function GET(request: Request) {
  return jsonResponse(ownerOpenApiDocument(new URL(request.url).origin));
}
