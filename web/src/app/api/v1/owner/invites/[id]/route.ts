import { notFound } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse } from "@/lib/api/http";
import { parseUuid } from "@/lib/api/validate";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

/** Revokes the invite. It stays listed, so the owner can see who had access. */
export async function DELETE(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:invites:manage", async () => {
    const id = parseUuid((await params).id, "id");
    const db = adminClient();
    const { data, error } = await db
      .from("invites")
      .update({ revoked_at: new Date().toISOString() })
      .eq("id", id)
      .is("revoked_at", null)
      .select("id, revoked_at");
    if (error) throw dbFailure(error, "revoke invite");
    if (data.length > 0) return jsonResponse({ revoked: true, revoked_at: data[0]!.revoked_at });

    const { data: existing, error: readError } = await db
      .from("invites")
      .select("revoked_at")
      .eq("id", id)
      .maybeSingle();
    if (readError) throw dbFailure(readError, "read invite");
    if (!existing) throw notFound("UNKNOWN_INVITE", "No invite has this id.");
    return jsonResponse({ revoked: true, revoked_at: existing.revoked_at });
  });
}
