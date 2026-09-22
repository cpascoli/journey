import { handleApiRequest, jsonResponse } from "@/lib/api/http";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

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

/**
 * Every conversation with something in it, newest first. One thread per
 * invitation per entry, because threads are private to the invitation.
 */
export async function GET(request: Request) {
  return handleApiRequest(request, "journey:comments:manage", async () => {
    const { data, error } = await adminClient().rpc("owner_comment_threads");
    if (error) throw dbFailure(error, "list comment threads");
    const threads = (data ?? []) as ThreadRow[];
    return jsonResponse({
      threads,
      unseen_total: threads.reduce((sum, thread) => sum + thread.unseen_count, 0),
    });
  });
}
