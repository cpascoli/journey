import type { SupabaseClient } from "@supabase/supabase-js";

import type { StorageProvider } from "@/lib/owner/media";
import type { VideoStore } from "@/lib/owner/video-upload";
import { MEDIA_BUCKET } from "@/lib/supabase/admin";

import {
  isR2Configured,
  r2Delete,
  r2Head,
  r2ReadHead,
  r2SignedReadUrl,
  r2SignedUploadUrl,
} from "./r2";

/**
 * Videos live in R2 in production. The localhost stack has no R2, so when it
 * is unconfigured they fall back to Supabase Storage, which keeps
 * `pnpm test:e2e:reader` able to exercise the whole upload path. Never point
 * this at the hosted project without R2 configured.
 */
export function videoProvider(
  env: Record<string, string | undefined> = process.env,
): StorageProvider {
  return isR2Configured(env) ? "r2" : "supabase";
}

function splitPath(path: string): { directory: string; name: string } {
  const cut = path.lastIndexOf("/");
  return { directory: path.slice(0, cut), name: path.slice(cut + 1) };
}

function supabaseVideoStore(db: SupabaseClient): VideoStore {
  return {
    async head(path) {
      const { directory, name } = splitPath(path);
      const { data, error } = await db.storage.from(MEDIA_BUCKET).list(directory, { search: name });
      const found = data?.find((item) => item.name === name);
      if (error || !found) return null;
      const metadata = (found.metadata ?? {}) as { size?: number; mimetype?: string };
      return { size: metadata.size ?? 0, contentType: metadata.mimetype ?? "" };
    },
    async readHead(path, length) {
      // Supabase Storage has no range download; the dev path reads the whole
      // object, which is why it is only ever used against localhost.
      const { data, error } = await db.storage.from(MEDIA_BUCKET).download(path);
      if (error || !data) return null;
      return new Uint8Array(await data.slice(0, length).arrayBuffer());
    },
    async remove(path) {
      const { error } = await db.storage.from(MEDIA_BUCKET).remove([path]);
      return !error;
    },
  };
}

function r2VideoStore(): VideoStore {
  return { head: r2Head, readHead: r2ReadHead, remove: r2Delete };
}

export function videoStore(db: SupabaseClient, provider = videoProvider()): VideoStore {
  return provider === "r2" ? r2VideoStore() : supabaseVideoStore(db);
}

export async function videoUploadUrl(
  db: SupabaseClient,
  path: string,
  expiresIn: number,
  contentType: string,
  provider = videoProvider(),
): Promise<string | null> {
  if (provider === "r2") return r2SignedUploadUrl(path, expiresIn, contentType);
  const { data, error } = await db.storage.from(MEDIA_BUCKET).createSignedUploadUrl(path);
  return error || !data ? null : data.signedUrl;
}

export function r2ReadUrl(path: string, expiresIn: number): string {
  return r2SignedReadUrl(path, expiresIn);
}
