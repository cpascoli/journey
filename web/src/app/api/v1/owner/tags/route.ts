import { handleApiRequest, jsonResponse } from "@/lib/api/http";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  return handleApiRequest(request, "journey:entries:read", async () => {
    const { data, error } = await adminClient()
      .from("tags")
      .select("id, name, color, updated_at")
      .order("name");
    if (error) throw dbFailure(error, "list tags");
    return jsonResponse({ tags: data });
  });
}
