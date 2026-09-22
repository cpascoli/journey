import { conflict, validationError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readJson } from "@/lib/api/http";
import { asObject, parseUuid, stringField } from "@/lib/api/validate";
import { MAX_COMMENT_LENGTH } from "@/lib/reader/comment-shape";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

/** One conversation: the comments between the owner and one invitation. */
export async function GET(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:comments:manage", async () => {
    const entryId = parseUuid((await params).id, "id");
    const invite = new URL(request.url).searchParams.get("invite");
    if (!invite) throw validationError("invite is required.", { field: "invite" });
    const { data, error } = await adminClient().rpc("owner_comment_thread", {
      p_entry_id: entryId,
      p_invite_id: parseUuid(invite, "invite"),
    });
    if (error) throw dbFailure(error, "read comment thread");
    return jsonResponse({ comments: data ?? [] });
  });
}

/** Replies inside an existing conversation. */
export async function POST(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:comments:manage", async () => {
    const entryId = parseUuid((await params).id, "id");
    const payload = asObject(await readJson(request));
    const inviteId = parseUuid(payload.invite_id, "invite_id");
    const body = stringField(payload, "body", { max: MAX_COMMENT_LENGTH, required: true });

    const { data, error } = await adminClient().rpc("post_owner_comment", {
      p_entry_id: entryId,
      p_invite_id: inviteId,
      p_body: body,
    });
    if (error) throw dbFailure(error, "post owner comment");
    const result = (data as { comment_id: string | null; refusal: string | null }[])[0];
    if (result?.refusal === "no_thread") {
      throw conflict("NO_THREAD", "This invitation has not commented on this entry.");
    }
    if (result?.refusal) throw validationError("The comment was refused.", { field: "body" });
    return jsonResponse({ comment: { id: result?.comment_id } }, 201);
  });
}

/** Marks an invitation's comments on this entry as seen. */
export async function PATCH(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:comments:manage", async () => {
    const entryId = parseUuid((await params).id, "id");
    const payload = asObject(await readJson(request));
    const inviteId = parseUuid(payload.invite_id, "invite_id");
    const { data, error } = await adminClient().rpc("mark_thread_seen", {
      p_entry_id: entryId,
      p_invite_id: inviteId,
    });
    if (error) throw dbFailure(error, "mark thread seen");
    return jsonResponse({ marked: data ?? 0 });
  });
}
