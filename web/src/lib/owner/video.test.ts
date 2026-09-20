import { describe, expect, it } from "vitest";

import { findMoov, findVideoMetadata, readVideoShape } from "./video";

function ascii(text: string): number[] {
  return [...text].map((character) => character.charCodeAt(0));
}

function uint32(value: number): number[] {
  return [(value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff];
}

/** An MP4 box: 4-byte size, 4-character type, then the body. */
function box(type: string, ...body: number[][]): number[] {
  const payload = body.flat();
  return [...uint32(payload.length + 8), ...ascii(type), ...payload];
}

function fixed1616(value: number): number[] {
  return uint32(Math.round(value * 65536));
}

const IDENTITY_MATRIX = [
  ...fixed1616(1), ...fixed1616(0), ...uint32(0),
  ...fixed1616(0), ...fixed1616(1), ...uint32(0),
  ...uint32(0), ...uint32(0), ...uint32(0x40000000),
];

/** a=0, d=0 with b and c set: the quarter turn iOS writes for a portrait clip. */
const ROTATED_MATRIX = [
  ...fixed1616(0), ...fixed1616(1), ...uint32(0),
  ...fixed1616(-1), ...fixed1616(0), ...uint32(0),
  ...uint32(0), ...uint32(0), ...uint32(0x40000000),
];

function tkhd(width: number, height: number, matrix = IDENTITY_MATRIX): number[] {
  return box("tkhd", [
    ...uint32(0), // version 0 and flags
    ...uint32(0), // creation
    ...uint32(0), // modification
    ...uint32(1), // track id
    ...uint32(0), // reserved
    ...uint32(0), // duration
    ...uint32(0), ...uint32(0), // reserved
    ...[0, 0], // layer
    ...[0, 0], // alternate group
    ...[0, 0], // volume
    ...[0, 0], // reserved
    ...matrix,
    ...fixed1616(width),
    ...fixed1616(height),
  ]);
}

function mvhd(timescale: number, duration: number): number[] {
  return box("mvhd", [
    ...uint32(0), // version 0 and flags
    ...uint32(0), // creation
    ...uint32(0), // modification
    ...uint32(timescale),
    ...uint32(duration),
  ]);
}

/** A fast-start file: ftyp, then moov, then the media data. */
function mp4(moovBody: number[][], { fastStart = true } = {}): Uint8Array {
  const ftyp = box("ftyp", ascii("isom"));
  const moov = box("moov", ...moovBody);
  const mdat = box("mdat", [1, 2, 3, 4]);
  return new Uint8Array(fastStart ? [...ftyp, ...moov, ...mdat] : [...ftyp, ...mdat, ...moov]);
}

const videoTrack = box("trak", tkhd(1280, 720));

describe("findMoov", () => {
  it("finds moov in a fast-start file", () => {
    expect(findMoov(mp4([videoTrack]))).not.toBeNull();
  });

  it("finds moov after the media data too, when the whole file is present", () => {
    expect(findMoov(mp4([videoTrack], { fastStart: false }))).not.toBeNull();
  });

  it("reports nothing when moov is cut short, rather than trusting a partial box", () => {
    // ftyp is 12 bytes, so 20 leaves moov's header present but its body missing.
    expect(findMoov(mp4([videoTrack]).slice(0, 20))).toBeNull();
  });

  it("reports nothing for bytes that are not an MP4 at all", () => {
    expect(findMoov(new Uint8Array([0xff, 0xd8, 0xff, 0xe0]))).toBeNull();
  });
});

describe("findVideoMetadata", () => {
  it("finds nothing in a stripped export", () => {
    expect(findVideoMetadata(mp4([videoTrack]))).toEqual([]);
  });

  it("finds the QuickTime location atom iOS writes", () => {
    const udta = box("udta", box("©xyz", ascii("+51.5074-000.1278/")));
    expect(findVideoMetadata(mp4([videoTrack, udta]))).toEqual(["quicktime-location"]);
  });

  it("finds a 3GPP location box", () => {
    const udta = box("udta", box("loci", ascii("London")));
    expect(findVideoMetadata(mp4([videoTrack, udta]))).toEqual(["3gpp-location"]);
  });

  it("finds the modern Apple location key, which is a string and not a box type", () => {
    const keys = box("keys", ascii("com.apple.quicktime.location.ISO6709"));
    const meta = box("meta", uint32(0), box("hdlr", ascii("mdta")), keys);
    expect(findVideoMetadata(mp4([videoTrack, meta]))).toEqual(["apple-location-key"]);
  });

  it("finds a GPS metadata track", () => {
    const track = box("trak", box("mdia", box("minf", box("stbl", box("gpmd", [0])))));
    expect(findVideoMetadata(mp4([videoTrack, track]))).toEqual(["gps-track"]);
  });

  it("reads a QuickTime meta box, which unlike ISO BMFF has no version prefix", () => {
    const meta = box("meta", box("hdlr", ascii("mdta")), box("©xyz", ascii("+51.5-0.1/")));
    expect(findVideoMetadata(mp4([videoTrack, meta]))).toEqual(["quicktime-location"]);
  });

  it("ignores location-looking bytes in the media data, which is outside moov", () => {
    const ftyp = box("ftyp", ascii("isom"));
    const moov = box("moov", videoTrack);
    const mdat = box("mdat", ascii("©xyzcom.apple.quicktime.location.ISO6709"));
    expect(findVideoMetadata(new Uint8Array([...ftyp, ...moov, ...mdat]))).toEqual([]);
  });

  it("finds nothing when moov is out of reach, so the caller must reject separately", () => {
    const whole = mp4([videoTrack], { fastStart: false });
    expect(findVideoMetadata(whole.slice(0, 16))).toEqual([]);
    expect(findMoov(whole.slice(0, 16))).toBeNull();
  });
});

describe("readVideoShape", () => {
  it("reads the track dimensions and the duration", () => {
    const shape = readVideoShape(mp4([mvhd(600, 1800), videoTrack]));
    expect(shape).toEqual({ width: 1280, height: 720, durationSeconds: 3 });
  });

  it("swaps the dimensions for a portrait clip's rotation matrix", () => {
    const portrait = box("trak", tkhd(1280, 720, ROTATED_MATRIX));
    expect(readVideoShape(mp4([portrait]))).toMatchObject({ width: 720, height: 1280 });
  });

  it("ignores an audio track, which carries zero dimensions", () => {
    const audio = box("trak", tkhd(0, 0));
    expect(readVideoShape(mp4([audio, videoTrack]))).toMatchObject({ width: 1280, height: 720 });
  });

  it("returns null when there is no video track to measure", () => {
    expect(readVideoShape(mp4([box("trak", tkhd(0, 0))]))).toBeNull();
    expect(readVideoShape(new Uint8Array([0, 1, 2, 3]))).toBeNull();
  });
});
