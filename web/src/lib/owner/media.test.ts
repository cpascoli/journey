import { describe, expect, it } from "vitest";

import { findPhotoMetadata, isJpeg, MEDIA_KEY_PATTERN, mediaStoragePath } from "./media";

function segment(marker: number, payload: string | number[]): number[] {
  const bytes = typeof payload === "string" ? [...payload].map((c) => c.charCodeAt(0)) : payload;
  const length = bytes.length + 2;
  return [0xff, marker, length >> 8, length & 0xff, ...bytes];
}

function jpeg(...segments: number[][]): Uint8Array {
  // SOI, the segments, then start of scan with a little image data, then EOI.
  return new Uint8Array([0xff, 0xd8, ...segments.flat(), ...segment(0xda, [0, 0, 0]), 0x12, 0x34, 0xff, 0xd9]);
}

const jfif = segment(0xe0, "JFIF\0");
const icc = segment(0xe2, "ICC_PROFILE\0");

describe("isJpeg", () => {
  it("recognises the JPEG signature", () => {
    expect(isJpeg(jpeg(jfif))).toBe(true);
    expect(isJpeg(new Uint8Array([0x89, 0x50, 0x4e, 0x47]))).toBe(false);
    expect(isJpeg(new Uint8Array([]))).toBe(false);
  });
});

describe("findPhotoMetadata", () => {
  it("finds nothing in a stripped photo with only JFIF and a colour profile", () => {
    expect(findPhotoMetadata(jpeg(jfif, icc))).toEqual([]);
  });

  it("finds EXIF, which carries GPS coordinates", () => {
    expect(findPhotoMetadata(jpeg(jfif, segment(0xe1, "Exif\0\0MM\0*")))).toEqual(["exif"]);
  });

  it("finds XMP and IPTC too", () => {
    const xmp = segment(0xe1, "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta/>");
    const iptc = segment(0xed, "Photoshop 3.0\0");
    expect(findPhotoMetadata(jpeg(xmp, iptc)).sort()).toEqual(["iptc", "xmp"]);
  });

  it("skips fill bytes before a marker", () => {
    const filled = [0xff, ...segment(0xe1, "Exif\0\0MM")];
    expect(findPhotoMetadata(jpeg(jfif, filled))).toEqual(["exif"]);
  });

  it("stops at the image data, so bytes inside it can't look like metadata", () => {
    const tricky = new Uint8Array([...jpeg(jfif), ...segment(0xe1, "Exif\0")]);
    expect(findPhotoMetadata(tricky)).toEqual([]);
  });
});

describe("media keys and paths", () => {
  it("accepts hash-like keys and rejects path characters", () => {
    expect(MEDIA_KEY_PATTERN.test("a1b2c3_D4-e5")).toBe(true);
    expect(MEDIA_KEY_PATTERN.test("4F5E/L0/001")).toBe(false);
    expect(MEDIA_KEY_PATTERN.test("")).toBe(false);
  });

  it("stores each photo under its entry", () => {
    expect(mediaStoragePath("e1", "k1")).toBe("entries/e1/k1.jpg");
  });
});
