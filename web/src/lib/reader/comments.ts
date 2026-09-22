import { cookies } from "next/headers";

import { INVITE_COOKIE } from "@/lib/auth/session";
import { hashInviteToken } from "@/lib/owner/invites";
import { adminClient } from "@/lib/supabase/admin";

import { MAX_COMMENT_LENGTH, type Comment, type Refusal } from "./comment-shape";

export { MAX_COMMENT_LENGTH };
export type { Comment, Refusal };

function inviteToken(store: Awaited<ReturnType<typeof cookies>>): string | null {
  const token = store.get(INVITE_COOKIE)?.value;
  return token && /^[A-Za-z0-9_-]{32}$/.test(token) ? token : null;
}

/**
 * The reader's own conversation on one entry.
 *
 * Authorization is entirely in `comment_thread_for_invite`, which returns
 * nothing unless the entry is still readable by this invitation — so a
 * revoked invitation, or one that lost a tag, sees no thread rather than a
 * filtered one.
 */
export async function threadForCurrentInvite(entryId: string): Promise<Comment[]> {
  const token = inviteToken(await cookies());
  if (!token) return [];
  const { data, error } = await adminClient().rpc("comment_thread_for_invite", {
    p_token_hash: hashInviteToken(token),
    p_entry_id: entryId,
  });
  if (error) {
    console.error("Could not load comments", error.code);
    return [];
  }
  return (data ?? []) as Comment[];
}

/** Adds the reader's comment, or returns why it was refused. */
export async function addCommentAsCurrentInvite(
  entryId: string,
  body: string,
): Promise<Refusal | null> {
  const token = inviteToken(await cookies());
  if (!token) return "not_readable";
  const { data, error } = await adminClient().rpc("post_reader_comment", {
    p_token_hash: hashInviteToken(token),
    p_entry_id: entryId,
    p_body: body,
  });
  if (error) {
    console.error("Could not post a comment", error.code);
    return "not_readable";
  }
  const result = (data as { comment_id: string | null; refusal: Refusal | null }[])[0];
  return result?.refusal ?? null;
}
