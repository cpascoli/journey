import { validationError } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse, readJson } from "@/lib/api/http";
import { asObject, parseUuid, queryInteger, stringField } from "@/lib/api/validate";
import { videoProvider, videoStore } from "@/lib/media/video-store";
import { parseMediaKey, parseStoragePath } from "@/lib/owner/media";
import { removeQueuedStorage } from "@/lib/owner/storage-cleanup";
import { VIDEO_CONTENT_TYPE } from "@/lib/owner/video";
import { verifyUploadedVideo } from "@/lib/owner/video-upload";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string; key: string }> };

/**
 * Records a video that has already been uploaded to the object store.
 *
 * The client names the path it uploaded to, so the path is checked against
 * the one this entry and key could have been given: an owner key must not be
 * able to point an entry's media row at an object belonging to another entry.
 */
export async function PUT(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const { id, key: rawKey } = await params;
    const entryId = parseUuid(id, "id");
    const key = parseMediaKey(rawKey);

    const body = asObject(await readJson(request));
    const storagePath = stringField(body, "storage_path", { max: 512, required: true });
    const { provider, path } = parseStoragePath(storagePath);
    if (provider !== videoProvider() || !path.startsWith(`entries/${entryId}/${key}/`)) {
      throw validationError("storage_path is not one issued for this media key.", {
        field: "storage_path",
      });
    }

    const query = new URL(request.url).searchParams;
    const sortOrder = queryInteger(query, "sort_order", { min: 0, max: 1_000 }) ?? 0;
    const takenAtRaw = query.get("taken_at");
    const takenAt = takenAtRaw && !Number.isNaN(Date.parse(takenAtRaw))
      ? new Date(takenAtRaw).toISOString()
      : null;
    if (takenAtRaw && !takenAt) {
      throw validationError("taken_at must be an ISO 8601 date-time.", { field: "taken_at" });
    }

    const db = adminClient();
    // Rejects and deletes anything carrying a location, not fast-start, or
    // oversized. The queue entry from upload-url stays until cleanup finishes.
    let video;
    try {
      video = await verifyUploadedVideo(videoStore(db, provider), path);
    } catch (error) {
      await removeQueuedStorage(db, [storagePath]);
      throw error;
    }

    const { data, error } = await db.rpc("commit_media_upload_v2", {
      p_entry_id: entryId,
      p_asset_key: key,
      p_storage_path: storagePath,
      p_kind: "video",
      p_content_type: VIDEO_CONTENT_TYPE,
      p_width: video.width,
      p_height: video.height,
      p_duration_seconds: video.durationSeconds,
      p_taken_at: takenAt,
      p_sort_order: sortOrder,
    });
    if (error) throw dbFailure(error, "record video");
    const previousPath = (data as { replaced_storage_path: string | null }[])[0]
      ?.replaced_storage_path;
    await removeQueuedStorage(db, previousPath ? [previousPath] : []);

    return jsonResponse({
      media: {
        asset_key: key,
        kind: "video",
        width: video.width,
        height: video.height,
        duration_seconds: video.durationSeconds,
        taken_at: takenAt,
        sort_order: sortOrder,
        bytes: video.bytes,
      },
    });
  });
}
