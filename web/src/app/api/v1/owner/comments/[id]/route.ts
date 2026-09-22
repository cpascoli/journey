import { notFound } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse } from "@/lib/api/http";
import { parseUuid } from "@/lib/api/validate";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

/** The owner may remove either side of a conversation. Readers cannot. */
export async function DELETE(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:comments:manage", async () => {
    const id = parseUuid((await params).id, "id");
    const { data, error } = await adminClient().rpc("delete_comment", { p_id: id });
    if (error) throw dbFailure(error, "delete comment");
    if (!data) throw notFound("UNKNOWN_COMMENT", "No comment has this id.");
    return jsonResponse({ deleted: true });
  });
}
