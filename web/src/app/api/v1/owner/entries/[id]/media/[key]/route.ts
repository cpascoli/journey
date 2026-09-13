import { ApiError, notFound, validationError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readBytes } from "@/lib/api/http";
import { parseUuid, queryInteger } from "@/lib/api/validate";
import {
  findPhotoMetadata,
  isJpeg,
  MAX_PHOTO_BYTES,
  MEDIA_KEY_PATTERN,
  mediaStoragePath,
} from "@/lib/owner/media";
import { adminClient, MEDIA_BUCKET } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string; key: string }> };

async function parseParams(params: Params["params"]) {
  const { id, key } = await params;
  if (!MEDIA_KEY_PATTERN.test(key)) {
    throw validationError(`key must match ${MEDIA_KEY_PATTERN.source}.`, { field: "key" });
  }
  return { entryId: parseUuid(id, "id"), key };
}

export async function PUT(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const { entryId, key } = await parseParams(params);
    const contentType = (request.headers.get("content-type") ?? "").split(";")[0]!.trim();
    if (contentType !== "image/jpeg") {
      throw new ApiError(415, "UNSUPPORTED_MEDIA_TYPE", "Upload photos as image/jpeg.");
    }
    const query = new URL(request.url).searchParams;
    const width = queryInteger(query, "width", { min: 1, max: 20_000 });
    const height = queryInteger(query, "height", { min: 1, max: 20_000 });
    const sortOrder = queryInteger(query, "sort_order", { min: 0, max: 1_000 }) ?? 0;
    const takenAtRaw = query.get("taken_at");
    const takenAt = takenAtRaw && !Number.isNaN(Date.parse(takenAtRaw)) ? new Date(takenAtRaw).toISOString() : null;
    if (takenAtRaw && !takenAt) {
      throw validationError("taken_at must be an ISO 8601 date-time.", { field: "taken_at" });
    }

    const bytes = await readBytes(request, MAX_PHOTO_BYTES);
    if (!isJpeg(bytes)) throw validationError("The body is not a JPEG image.", { field: "body" });
    const metadata = findPhotoMetadata(bytes);
    if (metadata.length > 0) {
      throw validationError(
        "Strip the photo's metadata before uploading: it can carry the exact location.",
        { field: "body", metadata },
      );
    }

    const db = adminClient();
    const { data: entry, error: entryError } = await db
      .from("entries")
      .select("id")
      .eq("id", entryId)
      .maybeSingle();
    if (entryError) throw dbFailure(entryError, "check entry");
    if (!entry) throw notFound("UNKNOWN_ENTRY", "Save the entry before uploading its photos.");

    const storagePath = mediaStoragePath(entryId, key);
    const { error: uploadError } = await db.storage
      .from(MEDIA_BUCKET)
      .upload(storagePath, bytes, { contentType: "image/jpeg", upsert: true });
    if (uploadError) throw dbFailure(uploadError, "upload photo");

    const row = {
      entry_id: entryId,
      asset_key: key,
      kind: "photo",
      storage_path: storagePath,
      width,
      height,
      taken_at: takenAt,
      sort_order: sortOrder,
    };
    const { error } = await db.from("entry_media").upsert(row, { onConflict: "entry_id,asset_key" });
    if (error) throw dbFailure(error, "record photo");

    const { storage_path: _path, entry_id: _entry, ...media } = row;
    return jsonResponse({ media: { ...media, bytes: bytes.byteLength } });
  });
}

export async function DELETE(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const { entryId, key } = await parseParams(params);
    const db = adminClient();
    const { data, error } = await db
      .from("entry_media")
      .delete()
      .eq("entry_id", entryId)
      .eq("asset_key", key)
      .select("storage_path");
    if (error) throw dbFailure(error, "delete photo row");
    const paths = (data as { storage_path: string }[]).map((row) => row.storage_path);
    if (paths.length > 0) {
      const { error: storageError } = await db.storage.from(MEDIA_BUCKET).remove(paths);
      if (storageError) throw dbFailure(storageError, "delete photo file");
    }
    return jsonResponse({ deleted: paths.length > 0 });
  });
}
