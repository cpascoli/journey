import { describe, expect, it } from "vitest";

import { isR2Configured, presignR2, type R2Config } from "./r2";

const config: R2Config = {
  accountId: "account",
  accessKeyId: "AKIAEXAMPLE",
  secretAccessKey: "secret",
  bucket: "journey-media",
};

const now = new Date("2026-09-20T10:30:00.000Z");

describe("presignR2", () => {
  /**
   * AWS's published example for a presigned S3 GET. Checking against their
   * value rather than one this file produced proves the signing chain itself,
   * not merely that it is stable.
   * https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
   */
  it("reproduces AWS's published SigV4 query-string signature", () => {
    const url = presignR2("GET", "test.txt", {
      expiresIn: 86400,
      now: new Date("2013-05-24T00:00:00.000Z"),
      region: "us-east-1",
      host: "examplebucket.s3.amazonaws.com",
      config: {
        accountId: "unused",
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        bucket: "",
      },
    });
    expect(url).toContain(
      "X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404",
    );
  });

  it("addresses R2 path-style, with the bucket in the path", () => {
    const url = new URL(presignR2("GET", "entries/abc/def.mp4", { expiresIn: 90, now, config }));
    expect(url.host).toBe("account.r2.cloudflarestorage.com");
    expect(url.pathname).toBe("/journey-media/entries/abc/def.mp4");
    expect(url.searchParams.get("X-Amz-Expires")).toBe("90");
    expect(url.searchParams.get("X-Amz-Algorithm")).toBe("AWS4-HMAC-SHA256");
    expect(url.searchParams.get("X-Amz-Credential")).toContain("/auto/s3/aws4_request");
  });

  it("signs the content type for an upload, so the body cannot arrive as something else", () => {
    const upload = new URL(
      presignR2("PUT", "entries/abc/def.mp4", {
        expiresIn: 600,
        now,
        config,
        contentType: "video/mp4",
      }),
    );
    expect(upload.searchParams.get("X-Amz-SignedHeaders")).toBe("content-type;host");

    const unpinned = new URL(presignR2("PUT", "entries/abc/def.mp4", { expiresIn: 600, now, config }));
    expect(unpinned.searchParams.get("X-Amz-SignedHeaders")).toBe("host");
    expect(unpinned.searchParams.get("X-Amz-Signature")).not.toBe(
      upload.searchParams.get("X-Amz-Signature"),
    );
  });

  it("signs the method and the path, so one URL cannot stand in for another", () => {
    const options = { expiresIn: 90, now, config };
    const read = new URL(presignR2("GET", "entries/a.mp4", options)).searchParams.get("X-Amz-Signature");
    const remove = new URL(presignR2("DELETE", "entries/a.mp4", options)).searchParams.get("X-Amz-Signature");
    const other = new URL(presignR2("GET", "entries/b.mp4", options)).searchParams.get("X-Amz-Signature");
    expect(new Set([read, remove, other]).size).toBe(3);
  });

  it("never puts the secret in the URL", () => {
    const url = presignR2("PUT", "entries/a.mp4", { expiresIn: 600, now, config });
    expect(url).not.toContain(config.secretAccessKey);
    expect(url).toContain(config.accessKeyId);
  });
});

describe("isR2Configured", () => {
  it("needs every credential before video storage counts as configured", () => {
    const full = {
      R2_ACCOUNT_ID: "a",
      R2_ACCESS_KEY_ID: "b",
      R2_SECRET_ACCESS_KEY: "c",
      R2_BUCKET: "d",
    };
    expect(isR2Configured(full)).toBe(true);
    expect(isR2Configured({ ...full, R2_BUCKET: undefined })).toBe(false);
    expect(isR2Configured({})).toBe(false);
  });
});
