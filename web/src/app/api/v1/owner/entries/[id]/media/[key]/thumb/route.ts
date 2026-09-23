import { randomUUID } from "node:crypto";

import { notFound, validationError } from "@/lib/api/errors";
import { ApiError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readBytes } from "@/lib/api/http";
import { parseUuid } from "@/lib/api/validate";
import {
  findPhotoMetadata,
  isJpeg,
  MAX_THUMBNAIL_BYTES,
  parseMediaKey,
  thumbnailStoragePath,
} from "@/lib/owner/media";
import { removeQueuedStorage } from "@/lib/owner/storage-cleanup";
import { adminClient, MEDIA_BUCKET } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string; key: string }> };

/**
 * The small copy shown in a grid, so reading an entry does not download every
 * photo at full size. It belongs to media that already exists — a thumbnail
 * cannot bring an entry's photo into being.
 *
 * Held to the same rule as the photo itself: it must arrive metadata-free,
 * because a thumbnail carries the same location a full image would.
 */
export async function PUT(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const { id, key: rawKey } = await params;
    const entryId = parseUuid(id, "id");
    const key = parseMediaKey(rawKey);

    const contentType = (request.headers.get("content-type") ?? "").split(";")[0]!.trim();
    if (contentType !== "image/jpeg") {
      throw new ApiError(415, "UNSUPPORTED_MEDIA_TYPE", "Upload thumbnails as image/jpeg.");
    }
    const bytes = await readBytes(request, MAX_THUMBNAIL_BYTES);
    if (!isJpeg(bytes)) throw validationError("The body is not a JPEG image.", { field: "body" });
    const metadata = findPhotoMetadata(bytes);
    if (metadata.length > 0) {
      throw validationError(
        "Strip the thumbnail's metadata before uploading: it can carry the exact location.",
        { field: "body", metadata },
      );
    }

    const db = adminClient();
    const path = thumbnailStoragePath(entryId, key, randomUUID());
    const { data: prepared, error: prepareError } = await db.rpc("prepare_media_upload", {
      p_entry_id: entryId,
      p_storage_path: path,
    });
    if (prepareError) throw dbFailure(prepareError, "prepare thumbnail upload");
    if (!prepared) throw notFound("UNKNOWN_ENTRY", "Save the entry before uploading thumbnails.");

    const { error: uploadError } = await db.storage
      .from(MEDIA_BUCKET)
      .upload(path, bytes, { contentType: "image/jpeg", upsert: false });
    if (uploadError) throw dbFailure(uploadError, "upload thumbnail");

    const { data, error } = await db.rpc("commit_media_thumbnail", {
      p_entry_id: entryId,
      p_asset_key: key,
      p_thumb_path: path,
    });
    if (error) throw dbFailure(error, "record thumbnail");
    if (!(data as { committed: boolean }[])[0]?.committed) {
      // Nothing references it now, so hand it straight back to cleanup.
      await removeQueuedStorage(db, [path]);
      throw notFound("UNKNOWN_MEDIA", "Upload the photo before its thumbnail.");
    }

    return jsonResponse({ thumbnail: { asset_key: key, bytes: bytes.byteLength } });
  });
}
