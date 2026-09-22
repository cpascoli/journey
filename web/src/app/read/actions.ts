"use server";

import { revalidatePath } from "next/cache";

import { requireSameOrigin } from "@/lib/auth/access";
import { MAX_COMMENT_LENGTH, type Refusal } from "@/lib/reader/comment-shape";
import { addCommentAsCurrentInvite } from "@/lib/reader/comments";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type CommentState = { refusal?: Refusal; body?: string };

/**
 * The only thing a reader may write. Authorization is not decided here: the
 * database refuses a comment on an entry this invitation cannot read, so this
 * validates shape, checks the request came from the site itself, and reports
 * the refusal.
 */
export async function addComment(
  _state: CommentState,
  formData: FormData,
): Promise<CommentState> {
  const entryId = formData.get("entry");
  const raw = formData.get("body");
  const body = typeof raw === "string" ? raw.trim() : "";

  try {
    await requireSameOrigin();
  } catch {
    return { refusal: "not_readable" };
  }
  if (typeof entryId !== "string" || !UUID.test(entryId)) {
    return { refusal: "not_readable" };
  }
  if (body.length === 0 || body.length > MAX_COMMENT_LENGTH) {
    // Hand the text back so a too-long comment is not lost on refusal.
    return { refusal: "bad_body", body };
  }

  const refusal = await addCommentAsCurrentInvite(entryId, body);
  if (refusal) return { refusal, body };
  revalidatePath(`/read/${entryId}`);
  return {};
}
