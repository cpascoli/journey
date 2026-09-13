import { conflict } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readJson } from "@/lib/api/http";
import { asObject, enumField, parseUuid, stringField } from "@/lib/api/validate";
import { TAG_COLORS } from "@/lib/owner/tags";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure, FOREIGN_KEY_VIOLATION } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

export async function PUT(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const id = parseUuid((await params).id, "id");
    const body = asObject(await readJson(request));
    const name = stringField(body, "name", { max: 60, required: true }).trim();
    const color = enumField(body, "color", TAG_COLORS, "blue");
    const { data, error } = await adminClient()
      .from("tags")
      .upsert({ id, name, color })
      .select("id, name, color, updated_at")
      .single();
    if (error) throw dbFailure(error, "upsert tag");
    return jsonResponse({ tag: data });
  });
}

function tagInUse(entries?: number) {
  return conflict(
    "TAG_IN_USE",
    "This tag is still on published entries. Remove it from them first: deleting it would leave them untagged, and untagged entries are visible to every invite.",
    entries === undefined ? {} : { entries },
  );
}

export async function DELETE(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const id = parseUuid((await params).id, "id");
    const db = adminClient();
    const { count, error: countError } = await db
      .from("entry_tags")
      .select("entry_id", { count: "exact", head: true })
      .eq("tag_id", id);
    if (countError) throw dbFailure(countError, "count tag uses");
    if ((count ?? 0) > 0) throw tagInUse(count ?? undefined);

    // The foreign key is the real guard: it also catches an entry tagged
    // between the count and the delete.
    const { data, error } = await db.from("tags").delete().eq("id", id).select("id");
    if (error) {
      if (error.code === FOREIGN_KEY_VIOLATION) throw tagInUse();
      throw dbFailure(error, "delete tag");
    }
    return jsonResponse({ deleted: data.length > 0 });
  });
}
