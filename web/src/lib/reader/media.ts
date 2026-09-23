import type { SupabaseClient } from "@supabase/supabase-js";

import { r2SignedReadUrl } from "@/lib/media/r2";
import { hashInviteToken } from "@/lib/owner/invites";
import { MEDIA_KEY_PATTERN, parseStoragePath } from "@/lib/owner/media";
import { MEDIA_BUCKET } from "@/lib/supabase/admin";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const INVITE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{32}$/;
export const MEDIA_URL_TTL_SECONDS = 90;
/**
 * Longer than a photo's, because a viewer can still be part-way through a clip
 * when a 90-second URL would have expired. Access is re-checked on every
 * request to /media, so this only bounds one already-authorised object.
 */
export const VIDEO_URL_TTL_SECONDS = 15 * 60;

/** Videos are the only media stored as .mp4; see `mediaStoragePath`. */
function ttlFor(storagePath: string): number {
  return storagePath.endsWith(".mp4") ? VIDEO_URL_TTL_SECONDS : MEDIA_URL_TTL_SECONDS;
}

type MediaAccess = {
  owner: boolean;
  inviteToken?: string;
  entryId: string;
  key: string;
  /** The grid asks for the small copy; opening one asks for the original. */
  wantsThumbnail?: boolean;
};

/** Where an item lives: the object, and the small copy when one was made. */
export type MediaPaths = { storage_path: string; thumb_path: string | null };

export type MediaReadServices = {
  ownerPath(entryId: string, key: string): Promise<MediaPaths | null>;
  invitePath(tokenHash: string, entryId: string, key: string): Promise<MediaPaths | null>;
  signedUrl(path: string, expiresIn: number): Promise<string | null>;
};

function unavailable(): Response {
  return new Response("Not Found", {
    status: 404,
    headers: {
      "Cache-Control": "private, no-store, max-age=0",
      "Content-Type": "text/plain; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export async function serveMedia(
  access: MediaAccess,
  services: MediaReadServices,
): Promise<Response> {
  if (!UUID_PATTERN.test(access.entryId) || !MEDIA_KEY_PATTERN.test(access.key)) return unavailable();

  let paths: MediaPaths | null = null;
  if (access.owner) {
    paths = await services.ownerPath(access.entryId, access.key);
  } else if (access.inviteToken && INVITE_TOKEN_PATTERN.test(access.inviteToken)) {
    paths = await services.invitePath(hashInviteToken(access.inviteToken), access.entryId, access.key);
  }
  if (!paths) return unavailable();

  // Falls back to the original, so media published before thumbnails existed
  // still loads rather than breaking.
  const path = (access.wantsThumbnail && paths.thumb_path) || paths.storage_path;
  const signedUrl = await services.signedUrl(path, ttlFor(path));
  if (!signedUrl) return unavailable();
  return new Response(null, {
    status: 302,
    headers: {
      "Cache-Control": "private, no-store, max-age=0",
      Location: signedUrl,
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export function supabaseMediaReadServices(db: SupabaseClient): MediaReadServices {
  return {
    async ownerPath(entryId, key) {
      const { data, error } = await db
        .from("entry_media")
        .select("storage_path, thumb_path")
        .eq("entry_id", entryId)
        .eq("asset_key", key)
        .maybeSingle();
      return error || !data ? null : (data as MediaPaths);
    },
    async invitePath(tokenHash, entryId, key) {
      const { data, error } = await db.rpc("media_visible_to_invite", {
        p_token_hash: tokenHash,
        p_entry_id: entryId,
        p_asset_key: key,
      });
      if (error || !data || data.length !== 1) return null;
      return data[0] as MediaPaths;
    },
    async signedUrl(storagePath, expiresIn) {
      // The path says which store holds the object: videos are on R2.
      const { provider, path } = parseStoragePath(storagePath);
      if (provider === "r2") return r2SignedReadUrl(path, expiresIn);
      const { data, error } = await db.storage.from(MEDIA_BUCKET).createSignedUrl(path, expiresIn);
      return error || !data ? null : data.signedUrl;
    },
  };
}
