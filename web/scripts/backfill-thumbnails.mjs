#!/usr/bin/env node
// Makes the small copy for photos published before thumbnails existed.
//
// A one-off. New photos get a thumbnail when the app publishes them; this is
// for everything already online, which would otherwise need every entry
// republished by hand from the phone.
//
// Reads the originals with the service-role key, resizes them here, and
// uploads through the owner API rather than writing to storage directly —
// so the JPEG check, the metadata refusal, the size limit and the
// cleanup-race guard are the same ones the app goes through. Nothing about
// what may be published is decided in this file.
//
//   SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… \
//   BASE_URL=https://ashone.me OWNER_TOKEN=… pnpm backfill:thumbnails
//   …same, with --apply, to actually write.
import { createClient } from "@supabase/supabase-js";
import sharp from "sharp";

/** Matches PhotoExport.thumbnailPixelSize in the iPhone app. */
const THUMBNAIL_PIXELS = 480;
/** The website's MAX_THUMBNAIL_BYTES. */
const MAX_THUMBNAIL_BYTES = 400 * 1024;
const MEDIA_BUCKET = "media";

const apply = process.argv.includes("--apply");
// pnpm passes its own "--" separator through, so it is not an argument.
const unknown = process.argv
  .slice(2)
  .filter((argument) => argument !== "--apply" && argument !== "--");
if (unknown.length > 0) {
  console.error(`Unknown argument: ${unknown[0]}`);
  process.exit(2);
}

const env = {
  SUPABASE_URL: process.env.SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
  BASE_URL: process.env.BASE_URL,
  OWNER_TOKEN: process.env.OWNER_TOKEN,
};
for (const [name, value] of Object.entries(env)) {
  if (!value) {
    console.error(`${name} is required.`);
    process.exit(2);
  }
}

const db = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const { data, error } = await db
  .from("entry_media")
  .select("entry_id, asset_key, storage_path, width, height")
  .eq("kind", "photo")
  .is("thumb_path", null)
  .order("entry_id");
if (error) {
  console.error("Could not list photos without a thumbnail.");
  process.exit(1);
}

const pending = data ?? [];
console.log(`Site:   ${env.BASE_URL}`);
console.log(`Photos without a small copy: ${pending.length}`);
if (pending.length === 0) process.exit(0);
if (!apply) {
  console.log("\nThis was a preview. Re-run with --apply to create them.");
  console.log("Nothing is replaced: only photos that have no thumbnail are touched.");
  process.exit(0);
}

let made = 0;
let failed = 0;
let skipped = 0;

for (const [index, row] of pending.entries()) {
  const label = `${row.entry_id.slice(0, 8)}…/${row.asset_key.slice(0, 8)}…`;
  const progress = `[${index + 1}/${pending.length}]`;
  try {
    const { data: file, error: downloadError } = await db.storage
      .from(MEDIA_BUCKET)
      .download(row.storage_path);
    if (downloadError || !file) {
      // The row points at an object that is gone; cleanup's problem, not ours.
      console.log(`${progress} skip  ${label} — the original could not be read`);
      skipped++;
      continue;
    }

    const original = Buffer.from(await file.arrayBuffer());
    let thumbnail = null;
    // Drop quality rather than give up, the way the app's export does.
    for (const quality of [80, 68, 55]) {
      const encoded = await sharp(original)
        .rotate() // honour the orientation before it is discarded
        .resize({
          width: THUMBNAIL_PIXELS,
          height: THUMBNAIL_PIXELS,
          fit: "inside",
          withoutEnlargement: true,
        })
        .jpeg({ quality, mozjpeg: true })
        .toBuffer();
      if (encoded.byteLength <= MAX_THUMBNAIL_BYTES) {
        thumbnail = encoded;
        break;
      }
    }
    if (!thumbnail) {
      console.log(`${progress} fail  ${label} — could not get it under the size limit`);
      failed++;
      continue;
    }

    // Through the API, so every rule the app obeys applies here too. sharp
    // writes no metadata unless asked, but the server is what decides that.
    const response = await fetch(
      `${env.BASE_URL}/api/v1/owner/entries/${row.entry_id}/media/${row.asset_key}/thumb`,
      {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${env.OWNER_TOKEN}`,
          "Content-Type": "image/jpeg",
        },
        body: thumbnail,
      },
    );
    if (!response.ok) {
      const body = (await response.text()).slice(0, 200);
      console.log(`${progress} fail  ${label} — ${response.status} ${body}`);
      failed++;
      continue;
    }
    console.log(`${progress} made  ${label} — ${Math.round(thumbnail.byteLength / 1024)} KB`);
    made++;
  } catch (cause) {
    console.log(`${progress} fail  ${label} — ${cause instanceof Error ? cause.message : cause}`);
    failed++;
  }
}

console.log(`\nDone: ${made} made, ${skipped} skipped, ${failed} failed.`);
// Safe to run again: it only ever looks at photos that still have no
// thumbnail, so a failed one is simply picked up next time.
process.exit(failed === 0 ? 0 : 1);
