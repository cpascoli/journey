import { ApiError, notFound, validationError } from "@/lib/api/errors";

import {
  findMoov,
  findVideoMetadata,
  MAX_VIDEO_BYTES,
  readVideoShape,
  VIDEO_CONTENT_TYPE,
  VIDEO_HEAD_BYTES,
  type VideoShape,
} from "./video";

/**
 * The object store, injected so this is testable without a network. The real
 * implementation is the R2 client; the localhost e2e stack substitutes
 * Supabase Storage.
 */
export type VideoStore = {
  head(path: string): Promise<{ size: number; contentType: string } | null>;
  readHead(path: string, length: number): Promise<Uint8Array | null>;
  remove(path: string): Promise<boolean>;
};

export type VerifiedVideo = VideoShape & { bytes: number };

/**
 * Checks an uploaded object before anything references it. The bytes went
 * straight from the phone to the object store, so this is the only point at
 * which the server sees them — it must be as strict as the photo route's
 * `findPhotoMetadata` check, which rejects rather than strips.
 *
 * A rejected object is deleted here, and its path stays on
 * `storage_cleanup_queue` until the caller finishes it, so a failure between
 * the two still leaves durable cleanup work.
 */
export async function verifyUploadedVideo(
  store: VideoStore,
  path: string,
): Promise<VerifiedVideo> {
  const object = await store.head(path);
  if (!object) {
    throw notFound("UPLOAD_MISSING", "Upload the video before committing it.");
  }

  const reject = async (error: ApiError): Promise<never> => {
    await store.remove(path);
    throw error;
  };

  if (object.size === 0) {
    return reject(validationError("The uploaded video is empty.", { field: "body" }));
  }
  if (object.size > MAX_VIDEO_BYTES) {
    return reject(
      validationError(`The video must be at most ${MAX_VIDEO_BYTES} bytes.`, {
        field: "body",
        bytes: object.size,
      }),
    );
  }
  if (object.contentType && !object.contentType.startsWith(VIDEO_CONTENT_TYPE)) {
    return reject(
      new ApiError(415, "UNSUPPORTED_MEDIA_TYPE", `Upload videos as ${VIDEO_CONTENT_TYPE}.`),
    );
  }

  const head = await store.readHead(path, VIDEO_HEAD_BYTES);
  if (!head) {
    return reject(validationError("The uploaded video could not be read.", { field: "body" }));
  }

  // Everything below is decided from `moov`. If it is not in the head, the
  // file is not fast-start and accepting it would mean trusting a part of the
  // file nobody inspected.
  if (!findMoov(head)) {
    return reject(
      validationError(
        "Export the video for streaming so its header comes first, then upload it again.",
        { field: "body" },
      ),
    );
  }

  const metadata = findVideoMetadata(head);
  if (metadata.length > 0) {
    return reject(
      validationError(
        "Strip the video's metadata before uploading: it can carry the exact location.",
        { field: "body", metadata },
      ),
    );
  }

  const shape = readVideoShape(head);
  if (!shape) {
    return reject(
      validationError("The upload has no readable video track.", { field: "body" }),
    );
  }
  return { ...shape, bytes: object.size };
}
