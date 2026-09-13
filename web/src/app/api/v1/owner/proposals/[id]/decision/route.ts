import { conflict, notFound } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readJson } from "@/lib/api/http";
import { asObject, enumField, parseUuid } from "@/lib/api/validate";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

/**
 * Records the owner's decision. Accepting does not change the entry here: the
 * app applies the text and republishes, so the entry only ever changes
 * through its owner.
 */
export async function POST(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:proposals:decide", async () => {
    const id = parseUuid((await params).id, "id");
    const decision = enumField(asObject(await readJson(request)), "decision", ["accepted", "rejected"] as const);
    const db = adminClient();
    const { data, error } = await db
      .from("narrative_proposals")
      .update({ status: decision, decided_at: new Date().toISOString() })
      .eq("id", id)
      .eq("status", "pending")
      .select("id, entry_id, status, decided_at");
    if (error) throw dbFailure(error, "decide proposal");
    if (data.length > 0) return jsonResponse({ proposal: data[0] });

    const { data: existing, error: readError } = await db
      .from("narrative_proposals")
      .select("status")
      .eq("id", id)
      .maybeSingle();
    if (readError) throw dbFailure(readError, "read proposal");
    if (!existing) throw notFound("UNKNOWN_PROPOSAL", "No proposal has this id.");
    throw conflict("PROPOSAL_ALREADY_DECIDED", `This proposal is already ${existing.status}.`, {
      status: existing.status,
    });
  });
}
