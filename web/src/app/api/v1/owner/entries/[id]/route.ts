import type { SupabaseClient } from "@supabase/supabase-js";

import { notFound, validationError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readJson } from "@/lib/api/http";
import { parseUuid } from "@/lib/api/validate";
import { parseEntryWrite } from "@/lib/owner/entries";
import { adminClient, MEDIA_BUCKET } from "@/lib/supabase/admin";
import { dbFailure, FOREIGN_KEY_VIOLATION } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

type MediaRow = {
  asset_key: string;
  kind: string;
  storage_path: string;
  width: number | null;
  height: number | null;
  taken_at: string | null;
  sort_order: number;
};

async function mediaOf(db: SupabaseClient, entryId: string): Promise<MediaRow[]> {
  const { data, error } = await db
    .from("entry_media")
    .select("asset_key, kind, storage_path, width, height, taken_at, sort_order")
    .eq("entry_id", entryId)
    .order("sort_order");
  if (error) throw dbFailure(error, "list media");
  return data as MediaRow[];
}

/**
 * Makes the entry's media match `keys`: removes rows and files that aren't
 * listed, orders the rest, and returns the keys still waiting for an upload.
 */
async function syncMedia(db: SupabaseClient, entryId: string, keys: string[]): Promise<string[]> {
  const existing = await mediaOf(db, entryId);
  const wanted = new Set(keys);
  const stale = existing.filter((row) => !wanted.has(row.asset_key));
  if (stale.length > 0) {
    const { error: storageError } = await db.storage
      .from(MEDIA_BUCKET)
      .remove(stale.map((row) => row.storage_path));
    if (storageError) throw dbFailure(storageError, "remove media files");
    const { error } = await db
      .from("entry_media")
      .delete()
      .eq("entry_id", entryId)
      .in("asset_key", stale.map((row) => row.asset_key));
    if (error) throw dbFailure(error, "remove media rows");
  }
  const have = new Set(existing.map((row) => row.asset_key));
  for (const [index, key] of keys.entries()) {
    if (!have.has(key)) continue;
    const { error } = await db
      .from("entry_media")
      .update({ sort_order: index })
      .eq("entry_id", entryId)
      .eq("asset_key", key);
    if (error) throw dbFailure(error, "order media");
  }
  return keys.filter((key) => !have.has(key));
}

export async function GET(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:read", async () => {
    const id = parseUuid((await params).id, "id");
    const db = adminClient();
    const { data: entry, error } = await db.from("entries").select("*").eq("id", id).maybeSingle();
    if (error) throw dbFailure(error, "read entry");
    if (!entry) throw notFound("UNKNOWN_ENTRY", "No published entry has this id.");
    const { data: tags, error: tagsError } = await db
      .from("entry_tags")
      .select("tag_id")
      .eq("entry_id", id);
    if (tagsError) throw dbFailure(tagsError, "read entry tags");
    const media = await mediaOf(db, id);
    return jsonResponse({
      entry: {
        ...entry,
        tag_ids: (tags as { tag_id: string }[]).map((row) => row.tag_id),
        media: media.map(({ storage_path: _path, ...row }) => row),
      },
    });
  });
}

export async function PUT(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const id = parseUuid((await params).id, "id");
    const write = parseEntryWrite(await readJson(request));
    const db = adminClient();
    const { data, error } = await db.rpc("save_entry", {
      p_id: id,
      p_fields: write.fields,
      p_tag_ids: write.tagIds,
    });
    if (error) {
      if (error.code === FOREIGN_KEY_VIOLATION) {
        throw validationError("tag_ids includes a tag the website doesn't have yet. Send the tag first.", {
          field: "tag_ids",
        });
      }
      throw dbFailure(error, "save entry");
    }
    const saved = (data as { saved_revision: number; was_created: boolean }[])[0]!;
    const missingMedia = write.mediaKeys ? await syncMedia(db, id, write.mediaKeys) : [];
    return jsonResponse(
      {
        entry: { id, revision: saved.saved_revision, visibility: write.fields.visibility },
        created: saved.was_created,
        missing_media: missingMedia,
      },
      saved.was_created ? 201 : 200,
    );
  });
}

export async function DELETE(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const id = parseUuid((await params).id, "id");
    const db = adminClient();
    const media = await mediaOf(db, id);
    if (media.length > 0) {
      const { error } = await db.storage.from(MEDIA_BUCKET).remove(media.map((row) => row.storage_path));
      if (error) throw dbFailure(error, "remove entry files");
    }
    const { data, error } = await db.from("entries").delete().eq("id", id).select("id");
    if (error) throw dbFailure(error, "delete entry");
    return jsonResponse({ deleted: data.length > 0 });
  });
}
