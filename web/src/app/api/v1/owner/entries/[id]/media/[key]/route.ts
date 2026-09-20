import { randomUUID } from "node:crypto";

import { ApiError, notFound, validationError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readBytes } from "@/lib/api/http";
import { parseUuid, queryInteger } from "@/lib/api/validate";
import {
  findPhotoMetadata,
  isJpeg,
  MAX_PHOTO_BYTES,
  mediaStoragePath,
  parseMediaKey,
} from "@/lib/owner/media";
import { removeQueuedStorage } from "@/lib/owner/storage-cleanup";
import { adminClient, MEDIA_BUCKET } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string; key: string }> };

async function parseParams(params: Params["params"]) {
  const { id, key } = await params;
  return { entryId: parseUuid(id, "id"), key: parseMediaKey(key) };
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
    // Every upload gets an immutable path. Queue it before Storage sees it so
    // a crash at any later point leaves durable orphan-cleanup work.
    const storagePath = mediaStoragePath(entryId, key, randomUUID());
    const { data: prepared, error: prepareError } = await db.rpc("prepare_media_upload", {
      p_entry_id: entryId,
      p_storage_path: storagePath,
    });
    if (prepareError) throw dbFailure(prepareError, "prepare photo upload");
    if (!prepared) throw notFound("UNKNOWN_ENTRY", "Save the entry before uploading its photos.");

    const { error: uploadError } = await db.storage
      .from(MEDIA_BUCKET)
      .upload(storagePath, bytes, { contentType: "image/jpeg", upsert: false });
    if (uploadError) throw dbFailure(uploadError, "upload photo");

    const { data, error } = await db.rpc("commit_media_upload_v2", {
      p_entry_id: entryId,
      p_asset_key: key,
      p_storage_path: storagePath,
      p_kind: "photo",
      p_content_type: "image/jpeg",
      p_width: width,
      p_height: height,
      p_duration_seconds: null,
      p_taken_at: takenAt,
      p_sort_order: sortOrder,
    });
    if (error) throw dbFailure(error, "record photo");
    const previousPath = (data as { replaced_storage_path: string | null }[])[0]
      ?.replaced_storage_path;
    await removeQueuedStorage(db, previousPath ? [previousPath] : []);

    return jsonResponse({
      media: {
        asset_key: key,
        kind: "photo",
        width,
        height,
        taken_at: takenAt,
        sort_order: sortOrder,
        bytes: bytes.byteLength,
      },
    });
  });
}

export async function DELETE(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const { entryId, key } = await parseParams(params);
    const db = adminClient();
    const { data, error } = await db.rpc("delete_entry_media", {
      p_entry_id: entryId,
      p_asset_key: key,
    });
    if (error) throw dbFailure(error, "delete photo row");
    const result = (data as { deleted: boolean; cleanup_paths: string[] }[])[0]!;
    await removeQueuedStorage(db, result.cleanup_paths);
    return jsonResponse({ deleted: result.deleted });
  });
}
