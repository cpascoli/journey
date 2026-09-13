import { API_VERSION } from "@/lib/api/version";

export const dynamic = "force-dynamic";

export function GET() {
  return Response.json(
    { name: "Journey API", version: API_VERSION, status: "ok" },
    { headers: { "Cache-Control": "no-store" } },
  );
}
