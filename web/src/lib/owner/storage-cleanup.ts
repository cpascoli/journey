import type { SupabaseClient } from "@supabase/supabase-js";

import { r2Delete } from "@/lib/media/r2";
import { parseStoragePath } from "@/lib/owner/media";
import { MEDIA_BUCKET } from "@/lib/supabase/admin";
import { dbFailure, type DbError } from "@/lib/supabase/errors";

const CLEANUP_ERROR_LIMIT = 500;

/**
 * Deletes one queued object from whichever store owns it. The queue holds
 * paths, not providers, so the path itself says where the object lives
 * (see `parseStoragePath`).
 */
async function removeObject(db: SupabaseClient, storedPath: string): Promise<DbError | null> {
  const { provider, path } = parseStoragePath(storedPath);
  if (provider === "r2") {
    try {
      return (await r2Delete(path)) ? null : { message: "R2 refused the delete." };
    } catch (error) {
      return { message: error instanceof Error ? error.message : "R2 delete failed." };
    }
  }
  const { error } = await db.storage.from(MEDIA_BUCKET).remove([path]);
  return error ?? null;
}

function safeError(error: DbError): string {
  return `${error.code ? `${error.code}: ` : ""}${error.message}`.slice(0, CLEANUP_ERROR_LIMIT);
}

async function finishStorageCleanup(
  db: SupabaseClient,
  path: string,
  removed: boolean,
  error?: DbError,
): Promise<void> {
  const { error: finishError } = await db.rpc("finish_storage_cleanup", {
    p_storage_path: path,
    p_removed: removed,
    p_last_error: error ? safeError(error) : null,
  });
  if (finishError) throw dbFailure(finishError, "finish storage cleanup");
}

/**
 * Paths must already be queued in the same transaction that removed their
 * references. Successful Storage removal clears the durable queue item;
 * failures remain queued with retry state.
 */
export async function removeQueuedStorage(
  db: SupabaseClient,
  paths: string[],
): Promise<void> {
  const uniquePaths = [...new Set(paths)];
  for (const path of uniquePaths) {
    const error = await removeObject(db, path);
    await finishStorageCleanup(db, path, !error, error ?? undefined);
  }
}

export type CleanupResult = {
  attempted: number;
  removed: number;
  failed: number;
};

/** Retries queued paths idempotently; removing an already-absent object is safe. */
export async function reconcileStorageCleanup(
  db: SupabaseClient,
  limit = 100,
): Promise<CleanupResult> {
  const boundedLimit = Math.max(1, Math.min(limit, 500));
  const { data, error } = await db.rpc("claim_storage_cleanup", {
    p_limit: boundedLimit,
  });
  if (error) throw dbFailure(error, "claim storage cleanup");

  const result: CleanupResult = { attempted: 0, removed: 0, failed: 0 };
  for (const row of (data ?? []) as { storage_path: string; attempts: number }[]) {
    result.attempted++;
    const removeError = await removeObject(db, row.storage_path);
    if (!removeError) {
      await finishStorageCleanup(db, row.storage_path, true);
      result.removed++;
      continue;
    }

    await finishStorageCleanup(db, row.storage_path, false, removeError);
    result.failed++;
  }
  return result;
}
