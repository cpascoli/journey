import { conflict, notFound } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse } from "@/lib/api/http";
import { publicOrigin } from "@/lib/api/origin";
import { parseUuid } from "@/lib/api/validate";
import { hashInviteToken, inviteUrl, newInviteToken } from "@/lib/owner/invites";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

/**
 * Replaces the invite's link. A token is shown once and only its hash is kept,
 * so an invitation closed before it was sent is otherwise stranded — the
 * invite exists but no one can reach it.
 *
 * The new hash overwrites the old one in a single statement, so the previous
 * link stops working at the moment this one starts. A revoked invite is not
 * rotated: that would quietly restore access.
 */
export async function POST(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:invites:manage", async () => {
    const id = parseUuid((await params).id, "id");
    const db = adminClient();
    const token = newInviteToken();

    const { data, error } = await db.rpc("rotate_invite_token", {
      p_invite_id: id,
      p_token_hash: hashInviteToken(token),
    });
    if (error) throw dbFailure(error, "rotate invite token");
    if ((data as { rotated: boolean }[])[0]?.rotated) {
      return jsonResponse({
        // Returned once. Only its hash is stored, so it can't be shown again.
        token,
        url: inviteUrl(publicOrigin(request.headers, request.url), token),
      });
    }

    const { data: existing, error: readError } = await db
      .from("invites")
      .select("revoked_at")
      .eq("id", id)
      .maybeSingle();
    if (readError) throw dbFailure(readError, "read invite");
    if (!existing) throw notFound("UNKNOWN_INVITE", "No invite has this id.");
    throw conflict("INVITE_REVOKED", "This invite is revoked. Create a new one instead.");
  });
}
