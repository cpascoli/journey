import { notFound, validationError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readJson } from "@/lib/api/http";
import { asObject, parseUuid, uuidArrayField } from "@/lib/api/validate";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure, FOREIGN_KEY_VIOLATION } from "@/lib/supabase/errors";

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

/**
 * Replaces the invite's tag set. Sent whole rather than as add/remove, and
 * applied in one SQL function, so the invite is never briefly readable by more
 * than intended — the same rule that puts entry tags inside `save_entry`.
 */
export async function PATCH(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:invites:manage", async () => {
    const id = parseUuid((await params).id, "id");
    const body = asObject(await readJson(request));
    const tagIds = uuidArrayField(body, "tag_ids", { max: 50 });

    const { data, error } = await adminClient().rpc("set_invite_tags", {
      p_invite_id: id,
      p_tag_ids: tagIds,
    });
    if (error) {
      if (error.code === FOREIGN_KEY_VIOLATION) {
        throw validationError("tag_ids includes a tag the website doesn't have yet.", {
          field: "tag_ids",
        });
      }
      throw dbFailure(error, "set invite tags");
    }
    const result = (data as { updated: boolean; tag_ids: string[] }[])[0]!;
    if (!result.updated) throw notFound("UNKNOWN_INVITE", "No invite has this id.");
    return jsonResponse({ invite: { id, tag_ids: result.tag_ids } });
  });
}
