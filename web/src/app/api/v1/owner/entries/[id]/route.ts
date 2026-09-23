import type { SupabaseClient } from "@supabase/supabase-js";

import { notFound, validationError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readJson } from "@/lib/api/http";
import { parseUuid } from "@/lib/api/validate";
import { parseEntryWrite } from "@/lib/owner/entries";
import { removeQueuedStorage } from "@/lib/owner/storage-cleanup";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure, FOREIGN_KEY_VIOLATION } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

type MediaRow = {
  asset_key: string;
  kind: string;
  storage_path: string;
  thumb_path: string | null;
  width: number | null;
  height: number | null;
  taken_at: string | null;
  sort_order: number;
};

async function mediaOf(db: SupabaseClient, entryId: string): Promise<MediaRow[]> {
  const { data, error } = await db
    .from("entry_media")
    .select("asset_key, kind, storage_path, thumb_path, width, height, taken_at, sort_order")
    .eq("entry_id", entryId)
    .order("sort_order");
  if (error) throw dbFailure(error, "list media");
  return data as MediaRow[];
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
        // Storage paths stay server-side; the app only needs to know whether
        // a small copy exists, so it can upload the ones still missing.
        media: media.map(({ storage_path: _path, thumb_path, ...row }) => ({
          ...row,
          thumb: thumb_path !== null,
        })),
      },
    });
  });
}

export async function PUT(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const id = parseUuid((await params).id, "id");
    const write = parseEntryWrite(await readJson(request));
    const db = adminClient();
    const { data, error } = await db.rpc("save_entry_with_media", {
      p_id: id,
      p_fields: write.fields,
      p_tag_ids: write.tagIds,
      p_media_keys: write.mediaKeys,
    });
    if (error) {
      if (error.code === FOREIGN_KEY_VIOLATION) {
        throw validationError("tag_ids includes a tag the website doesn't have yet. Send the tag first.", {
          field: "tag_ids",
        });
      }
      throw dbFailure(error, "save entry");
    }
    const saved = (data as {
      saved_revision: number;
      was_created: boolean;
      missing_media: string[];
      cleanup_paths: string[];
    }[])[0]!;
    await removeQueuedStorage(db, saved.cleanup_paths);
    return jsonResponse(
      {
        entry: { id, revision: saved.saved_revision, visibility: write.fields.visibility },
        created: saved.was_created,
        missing_media: saved.missing_media,
      },
      saved.was_created ? 201 : 200,
    );
  });
}

export async function DELETE(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const id = parseUuid((await params).id, "id");
    const db = adminClient();
    const { data, error } = await db.rpc("delete_entry_with_media", { p_id: id });
    if (error) throw dbFailure(error, "delete entry");
    const result = (data as { deleted: boolean; cleanup_paths: string[] }[])[0]!;
    await removeQueuedStorage(db, result.cleanup_paths);
    return jsonResponse({ deleted: result.deleted });
  });
}
