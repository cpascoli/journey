#!/usr/bin/env node
import { createClient } from "@supabase/supabase-js";

import { presign, R2_PATH_PREFIX, R2_REGION, r2Host } from "../src/lib/media/sigv4.mjs";

const apply = process.argv.includes("--apply");
const unknownArguments = process.argv.slice(2).filter((argument) => argument !== "--apply");
if (unknownArguments.length > 0) {
  console.error(`Unknown argument: ${unknownArguments[0]}`);
  process.exit(2);
}

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
  process.exit(2);
}

const db = createClient(url, key, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// Videos live in Cloudflare R2, photos in Supabase Storage; a queued path says
// which. Without R2 credentials this script can still reconcile photos, but it
// must not silently report an R2 object as handled.
const r2 = {
  accountId: process.env.R2_ACCOUNT_ID,
  accessKeyId: process.env.R2_ACCESS_KEY_ID,
  secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  bucket: process.env.R2_BUCKET,
};
const r2Configured = Boolean(r2.accountId && r2.accessKeyId && r2.secretAccessKey && r2.bucket);

async function removeObject(storagePath) {
  if (!storagePath.startsWith(R2_PATH_PREFIX)) {
    const { error: removeError } = await db.storage.from("media").remove([storagePath]);
    return removeError ? `${removeError.message}` : null;
  }
  if (!r2Configured) {
    return "R2 credentials are not set; cannot remove a video object.";
  }
  const path = storagePath.slice(R2_PATH_PREFIX.length);
  const signed = presign({
    method: "DELETE",
    path,
    bucket: r2.bucket,
    accessKeyId: r2.accessKeyId,
    secretAccessKey: r2.secretAccessKey,
    host: r2Host(r2.accountId),
    region: R2_REGION,
    expiresIn: 60,
  });
  try {
    const response = await fetch(signed, { method: "DELETE" });
    // An object already gone counts as removed, so cleanup is idempotent.
    return response.ok || response.status === 404 ? null : `R2 returned ${response.status}.`;
  } catch (cause) {
    return `R2 delete failed: ${cause instanceof Error ? cause.message : "unknown error"}`;
  }
}
const { data, error } = apply
  ? await db.rpc("claim_storage_cleanup", { p_limit: 100 })
  : await db
      .from("storage_cleanup_queue")
      .select("storage_path, attempts")
      .order("created_at")
      .limit(100);
if (error) {
  console.error("Could not read the cleanup queue.");
  process.exit(1);
}

const rows = data ?? [];
if (!apply) {
  const videos = rows.filter((row) => row.storage_path.startsWith(R2_PATH_PREFIX)).length;
  console.log(`${rows.length} queued object(s) would be retried (maximum batch: 100).`);
  console.log(`  ${rows.length - videos} in Supabase Storage, ${videos} in R2.`);
  if (videos > 0 && !r2Configured) {
    console.log("  R2 credentials are not set: those would be reported as failures.");
  }
  console.log("Run again with --apply after verifying SUPABASE_URL.");
  process.exit(0);
}

let removed = 0;
let failed = 0;
for (const row of rows) {
  const removeError = await removeObject(row.storage_path);
  const { error: finishError } = await db.rpc("finish_storage_cleanup", {
    p_storage_path: row.storage_path,
    p_removed: !removeError,
    p_last_error: removeError ? removeError.slice(0, 500) : null,
  });
  if (!removeError) {
    if (finishError) {
      console.error(`Could not finish queue item ${row.storage_path}.`);
      failed++;
    } else {
      removed++;
    }
    continue;
  }
  if (finishError) console.error(`Could not record failure for ${row.storage_path}.`);
  failed++;
}

console.log(`Cleanup complete: ${removed} removed, ${failed} failed.`);
process.exit(failed === 0 ? 0 : 1);
