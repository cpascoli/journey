import { jsonResponse } from "@/lib/api/http";
import { publicOrigin } from "@/lib/api/origin";
import { ownerOpenApiDocument } from "@/lib/api/owner-openapi";

export const dynamic = "force-dynamic";

/** Public: the contract describes the API, and every operation still needs the owner key. */
export function GET(request: Request) {
  return jsonResponse(ownerOpenApiDocument(publicOrigin(request.headers, request.url)));
}
