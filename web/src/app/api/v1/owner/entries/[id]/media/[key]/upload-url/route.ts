import { randomUUID } from "node:crypto";

import { ApiError, notFound } from "@/lib/api/errors";
import { handleApiRequest, jsonResponse } from "@/lib/api/http";
import { parseUuid } from "@/lib/api/validate";
import { videoProvider, videoUploadUrl } from "@/lib/media/video-store";
import { mediaStoragePath, parseMediaKey, qualifiedStoragePath } from "@/lib/owner/media";
import { MAX_VIDEO_BYTES, VIDEO_CONTENT_TYPE } from "@/lib/owner/video";
import { adminClient } from "@/lib/supabase/admin";
import { dbFailure } from "@/lib/supabase/errors";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string; key: string }> };

/** Long enough for a slow upload on mobile data, short enough to be worth little if leaked. */
const UPLOAD_TTL_SECONDS = 15 * 60;

/**
 * Starts a video upload. The bytes go straight from the phone to the object
 * store, because a Netlify function's request body caps at 6 MB and a video
 * does not fit — so, unlike a photo, the server sees the file only afterwards,
 * at the commit step, which is where it is verified.
 */
export async function POST(request: Request, { params }: Params) {
  return handleApiRequest(request, "journey:entries:write", async () => {
    const { id, key: rawKey } = await params;
    const entryId = parseUuid(id, "id");
    const key = parseMediaKey(rawKey);

    const db = adminClient();
    const provider = videoProvider();
    // A fresh immutable path per attempt, so a retry can never overwrite the
    // object a live media row still points at.
    const path = mediaStoragePath(entryId, key, randomUUID(), "video");
    const storagePath = qualifiedStoragePath(provider, path);

    // Queue the path before the store has anything at it: a crash from here
    // on leaves durable orphan-cleanup work rather than an unreferenced object.
    const { data: prepared, error: prepareError } = await db.rpc("prepare_media_upload", {
      p_entry_id: entryId,
      p_storage_path: storagePath,
    });
    if (prepareError) throw dbFailure(prepareError, "prepare video upload");
    if (!prepared) throw notFound("UNKNOWN_ENTRY", "Save the entry before uploading its videos.");

    const url = await videoUploadUrl(db, path, UPLOAD_TTL_SECONDS, VIDEO_CONTENT_TYPE, provider);
    if (!url) throw new ApiError(500, "STORAGE_ERROR", "Could not start the video upload.");

    return jsonResponse({
      upload: {
        url,
        storage_path: storagePath,
        content_type: VIDEO_CONTENT_TYPE,
        expires_in: UPLOAD_TTL_SECONDS,
        max_bytes: MAX_VIDEO_BYTES,
      },
    });
  });
}
