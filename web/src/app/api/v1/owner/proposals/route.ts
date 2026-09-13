import { validationError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse } from "@/lib/api/http";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

const STATUSES = ["pending", "accepted", "rejected", "superseded", "all"] as const;

type ProposalRow = {
  id: string;
  entry_id: string;
  base_revision: number;
  text: string;
  agent_name: string;
  status: string;
  created_at: string;
  decided_at: string | null;
  entries: { revision: number; title: string; day: string } | null;
};

export async function GET(request: Request) {
  return handleApiRequest(request, "journey:proposals:decide", async () => {
    const status = new URL(request.url).searchParams.get("status") ?? "pending";
    if (!(STATUSES as readonly string[]).includes(status)) {
      throw validationError(`status must be one of: ${STATUSES.join(", ")}.`, { field: "status" });
    }
    let query = adminClient()
      .from("narrative_proposals")
      .select("id, entry_id, base_revision, text, agent_name, status, created_at, decided_at, entries(revision, title, day)")
      .order("created_at", { ascending: false })
      .limit(200);
    if (status !== "all") query = query.eq("status", status);
    const { data, error } = await query;
    if (error) throw dbFailure(error, "list proposals");
    return jsonResponse({
      proposals: (data as unknown as ProposalRow[]).map(({ entries, ...proposal }) => ({
        ...proposal,
        entry_title: entries?.title ?? null,
        entry_day: entries?.day ?? null,
        entry_revision: entries?.revision ?? null,
        // Written against older text: the owner may still want it, but should know.
        stale: entries != null && proposal.base_revision < entries.revision,
      })),
    });
  });
}
