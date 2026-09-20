import { ApiError } from "@/lib/api/errors";

import { presign, R2_REGION, r2Host } from "./sigv4.mjs";

/**
 * Cloudflare R2, which holds published videos. It speaks S3, so every
 * operation here is a SigV4 presigned URL fetched with plain `fetch`: one
 * primitive, no SDK, and the same short-lived-URL shape the reader already
 * uses for Supabase Storage.
 *
 * The signing itself lives in `sigv4.mjs`, shared with the operator cleanup
 * script, which runs under bare node with no build step.
 *
 * Credentials are server-only. Never name them NEXT_PUBLIC_*, never log them.
 */

export type R2Config = {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
};

type Env = Record<string, string | undefined>;

export function r2Config(env: Env = process.env): R2Config {
  const accountId = env.R2_ACCOUNT_ID;
  const accessKeyId = env.R2_ACCESS_KEY_ID;
  const secretAccessKey = env.R2_SECRET_ACCESS_KEY;
  const bucket = env.R2_BUCKET;
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket) {
    throw new ApiError(500, "CONFIG", "Video storage is not configured on the server.");
  }
  return { accountId, accessKeyId, secretAccessKey, bucket };
}

export function isR2Configured(env: Env = process.env): boolean {
  return Boolean(
    env.R2_ACCOUNT_ID && env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY && env.R2_BUCKET,
  );
}

export type PresignOptions = {
  expiresIn: number;
  /** Signed, so the upload must send exactly this Content-Type. */
  contentType?: string;
  now?: Date;
  config?: R2Config;
  /**
   * Overridden only by the tests, so the signer can be checked against AWS's
   * published SigV4 vector rather than a value this file produced itself.
   */
  region?: string;
  host?: string;
};

export function presignR2(method: string, path: string, options: PresignOptions): string {
  const config = options.config ?? r2Config();
  return presign({
    method,
    path,
    bucket: config.bucket,
    accessKeyId: config.accessKeyId,
    secretAccessKey: config.secretAccessKey,
    host: options.host ?? r2Host(config.accountId),
    region: options.region ?? R2_REGION,
    expiresIn: options.expiresIn,
    contentType: options.contentType,
    now: options.now,
  });
}

const OPERATION_TTL_SECONDS = 60;

/** Size and content type of an object, or null when it is not there. */
export async function r2Head(path: string): Promise<{ size: number; contentType: string } | null> {
  const response = await fetch(presignR2("HEAD", path, { expiresIn: OPERATION_TTL_SECONDS }), {
    method: "HEAD",
  });
  if (!response.ok) return null;
  return {
    size: Number(response.headers.get("content-length") ?? 0),
    contentType: response.headers.get("content-type") ?? "",
  };
}

/** The first `length` bytes, for inspecting a fast-start MP4's header. */
export async function r2ReadHead(path: string, length: number): Promise<Uint8Array | null> {
  const response = await fetch(presignR2("GET", path, { expiresIn: OPERATION_TTL_SECONDS }), {
    headers: { Range: `bytes=0-${length - 1}` },
  });
  if (!response.ok) return null;
  return new Uint8Array(await response.arrayBuffer());
}

/** Removing an object that is already gone is a success, so cleanup can retry. */
export async function r2Delete(path: string): Promise<boolean> {
  const response = await fetch(presignR2("DELETE", path, { expiresIn: OPERATION_TTL_SECONDS }), {
    method: "DELETE",
  });
  return response.ok || response.status === 404;
}

export function r2SignedReadUrl(path: string, expiresIn: number): string {
  return presignR2("GET", path, { expiresIn });
}

export function r2SignedUploadUrl(path: string, expiresIn: number, contentType: string): string {
  return presignR2("PUT", path, { expiresIn, contentType });
}
