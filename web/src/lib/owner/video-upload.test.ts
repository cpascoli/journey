import { describe, expect, it, vi } from "vitest";

import { ApiError } from "@/lib/api/errors";

import { MAX_VIDEO_BYTES } from "./video";
import { verifyUploadedVideo, type VideoStore } from "./video-upload";

function ascii(text: string): number[] {
  return [...text].map((character) => character.charCodeAt(0));
}

function uint32(value: number): number[] {
  return [(value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff];
}

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

const tkhd = box("tkhd", [
  ...uint32(0), ...uint32(0), ...uint32(0), ...uint32(1), ...uint32(0), ...uint32(0),
  ...uint32(0), ...uint32(0), 0, 0, 0, 0, 0, 0, 0, 0,
  ...IDENTITY_MATRIX,
  ...fixed1616(1280), ...fixed1616(720),
]);

const mvhd = box("mvhd", [...uint32(0), ...uint32(0), ...uint32(0), ...uint32(600), ...uint32(1800)]);

function mp4(...extraMoovBoxes: number[][]): Uint8Array {
  return new Uint8Array([
    ...box("ftyp", ascii("isom")),
    ...box("moov", mvhd, box("trak", tkhd), ...extraMoovBoxes),
    ...box("mdat", [1, 2, 3, 4]),
  ]);
}

function store(bytes: Uint8Array | null, overrides: Partial<VideoStore> = {}) {
  const remove = vi.fn().mockResolvedValue(true);
  const fake: VideoStore = {
    head: async () => (bytes ? { size: bytes.byteLength, contentType: "video/mp4" } : null),
    readHead: async () => bytes,
    remove,
    ...overrides,
  };
  return { store: fake, remove };
}

async function rejection(promise: Promise<unknown>): Promise<ApiError> {
  try {
    await promise;
  } catch (error) {
    return error as ApiError;
  }
  throw new Error("Expected the upload to be rejected.");
}

describe("verifyUploadedVideo", () => {
  it("accepts a stripped fast-start export and measures it", async () => {
    const bytes = mp4();
    const { store: fake, remove } = store(bytes);
    await expect(verifyUploadedVideo(fake, "entries/e1/v.mp4")).resolves.toEqual({
      width: 1280,
      height: 720,
      durationSeconds: 3,
      bytes: bytes.byteLength,
    });
    expect(remove).not.toHaveBeenCalled();
  });

  it("refuses a video that still carries a location, and deletes it", async () => {
    const located = mp4(box("udta", box("©xyz", ascii("+51.5-0.1/"))));
    const { store: fake, remove } = store(located);

    const error = await rejection(verifyUploadedVideo(fake, "entries/e1/v.mp4"));
    expect(error.status).toBe(422);
    expect(error.details.metadata).toEqual(["quicktime-location"]);
    expect(remove).toHaveBeenCalledWith("entries/e1/v.mp4");
  });

  it("refuses a file whose header is not at the front, so nothing is trusted unread", async () => {
    const notFastStart = new Uint8Array([
      ...box("ftyp", ascii("isom")),
      ...box("mdat", new Array(64).fill(7)),
      ...box("moov", mvhd, box("trak", tkhd)),
    ]);
    // Only the head is read, and moov is past it.
    const { store: fake, remove } = store(notFastStart, {
      readHead: async () => notFastStart.slice(0, 20),
    });

    const error = await rejection(verifyUploadedVideo(fake, "entries/e1/v.mp4"));
    expect(error.status).toBe(422);
    expect(error.message).toContain("streaming");
    expect(remove).toHaveBeenCalled();
  });

  it("refuses an oversized upload without reading it", async () => {
    const readHead = vi.fn();
    const { store: fake, remove } = store(mp4(), {
      head: async () => ({ size: MAX_VIDEO_BYTES + 1, contentType: "video/mp4" }),
      readHead,
    });

    const error = await rejection(verifyUploadedVideo(fake, "entries/e1/v.mp4"));
    expect(error.status).toBe(422);
    expect(readHead).not.toHaveBeenCalled();
    expect(remove).toHaveBeenCalled();
  });

  it("refuses something that is not a video", async () => {
    const { store: fake } = store(mp4(), {
      head: async () => ({ size: 12, contentType: "image/jpeg" }),
    });
    expect((await rejection(verifyUploadedVideo(fake, "entries/e1/v.mp4"))).status).toBe(415);
  });

  it("refuses an MP4 with no video track to measure", async () => {
    const audioOnly = new Uint8Array([
      ...box("ftyp", ascii("isom")),
      ...box("moov", mvhd),
      ...box("mdat", [1]),
    ]);
    const { store: fake, remove } = store(audioOnly);
    expect((await rejection(verifyUploadedVideo(fake, "entries/e1/v.mp4"))).status).toBe(422);
    expect(remove).toHaveBeenCalled();
  });

  it("reports a missing object as not found, and leaves nothing to delete", async () => {
    const { store: fake, remove } = store(null);
    expect((await rejection(verifyUploadedVideo(fake, "entries/e1/v.mp4"))).status).toBe(404);
    expect(remove).not.toHaveBeenCalled();
  });

  it("refuses an empty object", async () => {
    const { store: fake } = store(new Uint8Array(), {
      head: async () => ({ size: 0, contentType: "video/mp4" }),
    });
    expect((await rejection(verifyUploadedVideo(fake, "entries/e1/v.mp4"))).status).toBe(422);
  });
});
