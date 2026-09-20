import { createHash, createHmac } from "node:crypto";

/**
 * SigV4 query-string presigning for S3-compatible stores (R2).
 *
 * Plain ESM rather than TypeScript so the operator script
 * (`scripts/reconcile-media-cleanup.mjs`, which runs under bare node with no
 * build step) and the server share one implementation. Signing code must not
 * exist twice: two copies drift, and a drifted signer fails in ways that look
 * like a credentials problem.
 */

const ALGORITHM = "AWS4-HMAC-SHA256";
const SERVICE = "s3";

function sha256Hex(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function hmac(key, value) {
  return createHmac("sha256", key).update(value, "utf8").digest();
}

/** Each path segment is encoded, but the separators are not. */
function encodePath(path) {
  return path.split("/").map((segment) => encodeURIComponent(segment)).join("/");
}

/** RFC 3986: encodeURIComponent leaves !'()* alone, and SigV4 does not. */
function encodeQueryComponent(value) {
  return encodeURIComponent(value).replace(
    /[!'()*]/g,
    (character) => `%${character.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

function amzDate(now) {
  const stamp = now.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  return { stamp, date: stamp.slice(0, 8) };
}

/**
 * A presigned URL for one object operation. The payload is unsigned, which is
 * what lets a phone stream a video straight to the store without the bytes
 * passing through a serverless function.
 *
 * @param {object} options
 * @param {string} options.method
 * @param {string} options.path Object key within the bucket.
 * @param {string} options.accessKeyId
 * @param {string} options.secretAccessKey
 * @param {string} options.host
 * @param {string} options.region
 * @param {number} options.expiresIn Seconds.
 * @param {string} [options.bucket] Empty when the host already names it.
 * @param {string} [options.contentType] Signed, pinning the upload's type.
 * @param {Date} [options.now]
 * @returns {string}
 */
export function presign(options) {
  const { stamp, date } = amzDate(options.now ?? new Date());
  const scope = `${date}/${options.region}/${SERVICE}/aws4_request`;
  const canonicalUri = options.bucket
    ? `/${encodePath(options.bucket)}/${encodePath(options.path)}`
    : `/${encodePath(options.path)}`;

  const signedHeaderNames = options.contentType ? ["content-type", "host"] : ["host"];
  const canonicalHeaders = signedHeaderNames
    .map((name) =>
      name === "host" ? `host:${options.host}\n` : `content-type:${options.contentType}\n`,
    )
    .join("");
  const signedHeaders = signedHeaderNames.join(";");

  const canonicalQuery = [
    ["X-Amz-Algorithm", ALGORITHM],
    ["X-Amz-Credential", `${options.accessKeyId}/${scope}`],
    ["X-Amz-Date", stamp],
    ["X-Amz-Expires", String(options.expiresIn)],
    ["X-Amz-SignedHeaders", signedHeaders],
  ]
    .map(([name, value]) => [encodeQueryComponent(name), encodeQueryComponent(value)])
    .sort((left, right) => (left[0] < right[0] ? -1 : left[0] > right[0] ? 1 : 0))
    .map(([name, value]) => `${name}=${value}`)
    .join("&");

  const canonicalRequest = [
    options.method.toUpperCase(),
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    "UNSIGNED-PAYLOAD",
  ].join("\n");

  const stringToSign = [ALGORITHM, stamp, scope, sha256Hex(canonicalRequest)].join("\n");
  const signingKey = hmac(
    hmac(hmac(hmac(`AWS4${options.secretAccessKey}`, date), options.region), SERVICE),
    "aws4_request",
  );
  const signature = createHmac("sha256", signingKey).update(stringToSign, "utf8").digest("hex");

  return `https://${options.host}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

/** The R2 S3 endpoint for an account. */
export function r2Host(accountId) {
  return `${accountId}.r2.cloudflarestorage.com`;
}

/** R2 is single-region; "auto" is what its S3 endpoint expects. */
export const R2_REGION = "auto";

/** Videos are stored with this prefix so the path alone says which store holds them. */
export const R2_PATH_PREFIX = "r2:";
