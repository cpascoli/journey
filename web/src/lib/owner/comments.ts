import type { SupabaseClient } from "@supabase/supabase-js";

import type { OwnerComment, OwnerThread } from "@/app/owner/Conversations";

type ThreadRow = {
  entry_id: string;
  entry_title: string;
  entry_day: string;
  invite_id: string;
  invite_name: string;
  invite_revoked: boolean;
  comment_count: number;
  unseen_count: number;
  last_at: string;
};

export type ThreadSummary = ThreadRow;

/** Every conversation, for the dashboard's inbox. */
export async function commentThreads(db: SupabaseClient): Promise<ThreadSummary[]> {
  const { data, error } = await db.rpc("owner_comment_threads");
  if (error) throw new Error("Could not load conversations.");
  return (data ?? []) as ThreadRow[];
}

/**
 * The conversations on one entry, with their comments. One request per
 * thread, because threads are separate conversations rather than one list.
 */
export async function conversationsForEntry(
  db: SupabaseClient,
  entryId: string,
): Promise<OwnerThread[]> {
  const summaries = (await commentThreads(db)).filter((row) => row.entry_id === entryId);
  return Promise.all(
    summaries.map(async (summary) => {
      const { data, error } = await db.rpc("owner_comment_thread", {
        p_entry_id: entryId,
        p_invite_id: summary.invite_id,
      });
      if (error) throw new Error("Could not load a conversation.");
      return {
        entryId,
        inviteId: summary.invite_id,
        inviteName: summary.invite_name,
        inviteRevoked: summary.invite_revoked,
        unseen: summary.unseen_count,
        comments: (data ?? []) as OwnerComment[],
      };
    }),
  );
}
