#!/usr/bin/env node
// Proves the R2 credentials and the SigV4 signer against the real service, by
// doing exactly what publishing a video does: a signed upload with a pinned
// content type, a HEAD, a ranged read of the head of the object, then a
// delete. Unit tests check the signer against AWS's published vector; only
// this catches a wrong account id, a mis-scoped token, or a missing bucket.
//
// It touches one object under _healthcheck/ and removes it. It never reads,
// writes or deletes anything under entries/.
import { randomUUID } from "node:crypto";

import { presign, R2_REGION, r2Host } from "../src/lib/media/sigv4.mjs";

const config = {
  accountId: process.env.R2_ACCOUNT_ID,
  accessKeyId: process.env.R2_ACCESS_KEY_ID,
  secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  bucket: process.env.R2_BUCKET,
};

const missing = Object.entries(config).filter(([, value]) => !value).map(([name]) => name);
if (missing.length > 0) {
  console.error(`Not configured. Missing: ${missing.join(", ")}.`);
  console.error("Set them in web/.env.local (see .env.example).");
  process.exit(2);
}

// A bucket name is a single path segment; a pasted S3 endpoint URL is the
// classic mistake and would otherwise fail as an opaque signature error.
if (config.bucket.includes("/") || config.bucket.includes(":")) {
  console.error(`R2_BUCKET must be just the bucket name, not a URL. Got: ${config.bucket}`);
  process.exit(2);
}

let failures = 0;
function check(label, ok, detail) {
  if (ok) {
    console.log(`  ok   ${label}`);
    return true;
  }
  failures++;
  console.log(`  FAIL ${label}${detail === undefined ? "" : ` — ${detail}`}`);
  return false;
}

function sign(method, path, options = {}) {
  return presign({
    method,
    path,
    bucket: config.bucket,
    accessKeyId: config.accessKeyId,
    secretAccessKey: config.secretAccessKey,
    host: r2Host(config.accountId),
    region: R2_REGION,
    expiresIn: 60,
    ...options,
  });
}

// Small but big enough to ask for a byte range across it.
const body = Buffer.from(`journey r2 healthcheck ${new Date().toISOString()} ${"x".repeat(256)}`);
const path = `_healthcheck/${randomUUID()}.mp4`;

console.log(`R2 round-trip against ${config.bucket} (${r2Host(config.accountId)})`);

let uploaded = false;
try {
  // 1. Upload with the content type signed into the URL, as upload-url does.
  const put = await fetch(sign("PUT", path, { contentType: "video/mp4", expiresIn: 300 }), {
    method: "PUT",
    headers: { "Content-Type": "video/mp4" },
    body,
  });
  uploaded = put.ok;
  if (!check("signed upload accepted", put.ok, `${put.status} ${(await put.text()).slice(0, 300)}`)) {
    // Everything after this needs the object, so stop with a useful hint.
    if (put.status === 403) console.log("       403 usually means a wrong secret, or a token not scoped to this bucket.");
    if (put.status === 404) console.log("       404 usually means the bucket name or account id is wrong.");
    throw new Error("upload failed");
  }

  // 2. HEAD: how the commit step learns an upload's size and type.
  const head = await fetch(sign("HEAD", path), { method: "HEAD" });
  check("HEAD reports the object", head.ok, `status ${head.status}`);
  check(
    `HEAD reports the right size (${body.byteLength})`,
    Number(head.headers.get("content-length")) === body.byteLength,
    head.headers.get("content-length"),
  );
  check(
    "HEAD reports the content type the upload pinned",
    (head.headers.get("content-type") ?? "").startsWith("video/mp4"),
    head.headers.get("content-type"),
  );

  // 3. Ranged read: video verification reads only the head of the file, and
  //    the browser seeks with ranges, so this must work.
  const ranged = await fetch(sign("GET", path), { headers: { Range: "bytes=0-31" } });
  const rangedBytes = new Uint8Array(await ranged.arrayBuffer());
  check("ranged read returns 206 Partial Content", ranged.status === 206, `status ${ranged.status}`);
  check("ranged read returns exactly the bytes asked for", rangedBytes.byteLength === 32, rangedBytes.byteLength);
  check(
    "ranged bytes match what was uploaded",
    Buffer.from(rangedBytes).equals(body.subarray(0, 32)),
  );

  // 4. An unsigned request must not work: the bucket has to stay private.
  const unsigned = await fetch(`https://${r2Host(config.accountId)}/${config.bucket}/${path}`);
  check("the object is not readable without a signature", !unsigned.ok, `status ${unsigned.status}`);
} catch (error) {
  if (error instanceof Error && error.message !== "upload failed") {
    failures++;
    console.log(`  FAIL unexpected error — ${error.message}`);
  }
} finally {
  if (uploaded) {
    const remove = await fetch(sign("DELETE", path), { method: "DELETE" });
    check("delete removes the object", remove.ok || remove.status === 404, `status ${remove.status}`);
    const gone = await fetch(sign("HEAD", path), { method: "HEAD" });
    check("the object is gone afterwards", gone.status === 404, `status ${gone.status}`);
  }
}

console.log(failures === 0 ? "\nR2 is configured correctly." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
