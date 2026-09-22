import { validationError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readJson } from "@/lib/api/http";
import { publicOrigin } from "@/lib/api/origin";
import { asObject, stringField, uuidArrayField } from "@/lib/api/validate";
import { hashInviteToken, inviteUrl, newInviteToken } from "@/lib/owner/invites";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure, FOREIGN_KEY_VIOLATION } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type InviteRow = {
  id: string;
  name: string;
  created_at: string;
  revoked_at: string | null;
  last_seen_at: string | null;
  invite_tags: { tag_id: string }[];
};

export async function GET(request: Request) {
  return handleApiRequest(request, "journey:invites:manage", async () => {
    const { data, error } = await adminClient()
      .from("invites")
      .select("id, name, created_at, revoked_at, last_seen_at, invite_tags(tag_id)")
      .order("created_at", { ascending: false });
    if (error) throw dbFailure(error, "list invites");
    const rows = data as InviteRow[];

    // What each invite can actually read. The all-tags rule is subtle and the
    // failure mode is over-sharing, so the app shows this before a link is sent.
    const counts = await Promise.all(
      rows.map(async (invite) => {
        if (invite.revoked_at) return 0;
        const { data: count, error: countError } = await adminClient().rpc(
          "invite_visible_entry_count",
          { p_invite_id: invite.id },
        );
        return countError ? null : (count as number);
      }),
    );

    return jsonResponse({
      invites: rows.map(({ invite_tags, ...invite }, index) => ({
        ...invite,
        tag_ids: invite_tags.map((row) => row.tag_id),
        visible_entry_count: counts[index],
      })),
    });
  });
}

export async function POST(request: Request) {
  return handleApiRequest(request, "journey:invites:manage", async () => {
    const body = asObject(await readJson(request));
    const name = stringField(body, "name", { max: 100, required: true }).trim();
    const tagIds = uuidArrayField(body, "tag_ids", { max: 50 });
    const token = newInviteToken();
    const { data, error } = await adminClient().rpc("create_invite", {
      p_name: name,
      p_token_hash: hashInviteToken(token),
      p_tag_ids: tagIds,
    });
    if (error) {
      if (error.code === FOREIGN_KEY_VIOLATION) {
        throw validationError("tag_ids includes a tag the website doesn't have yet.", { field: "tag_ids" });
      }
      throw dbFailure(error, "create invite");
    }
    const created = (data as { new_invite_id: string; new_created_at: string }[])[0]!;
    return jsonResponse(
      {
        invite: { id: created.new_invite_id, name, tag_ids: tagIds, created_at: created.new_created_at },
        // Returned once. Only its hash is stored, so it can't be shown again.
        token,
        url: inviteUrl(publicOrigin(request.headers, request.url), token),
      },
      201,
    );
  });
}
