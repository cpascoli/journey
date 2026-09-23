import { describe, expect, it, vi } from "vitest";

import {
  MEDIA_URL_TTL_SECONDS,
  serveMedia,
  VIDEO_URL_TTL_SECONDS,
  type MediaReadServices,
} from "./media";

const entryId = "00000000-0000-4000-8000-00000000e001";
const key = "photo_key";
const inviteToken = "a".repeat(32);
const storagePath = "entries/private/photo.jpg";

function services(overrides: Partial<MediaReadServices> = {}): MediaReadServices {
  return {
    ownerPath: vi.fn().mockResolvedValue(null),
    invitePath: vi.fn().mockResolvedValue(null),
    signedUrl: vi.fn().mockResolvedValue(null),
    ...overrides,
  };
}

describe("media route authorization", () => {
  it("allows a signed owner session to read private entry media", async () => {
    const deps = services({
      ownerPath: vi.fn().mockResolvedValue({ storage_path: storagePath, thumb_path: null }),
      signedUrl: vi.fn().mockResolvedValue("https://storage.test/signed"),
    });
    const response = await serveMedia({ owner: true, entryId, key }, deps);
    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe("https://storage.test/signed");
    expect(response.headers.get("cache-control")).toContain("private");
    expect(deps.signedUrl).toHaveBeenCalledWith(storagePath, MEDIA_URL_TTL_SECONDS);
  });

  it("returns the same generic 404 with no cookie", async () => {
    const response = await serveMedia({ owner: false, entryId, key }, services());
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("Not Found");
  });

  it.each([
    "invalid invite",
    "revoked invite",
    "under-tagged invite",
    "private entry for invite",
    "missing media",
  ])("does not disclose existence for %s", async () => {
    const deps = services({ invitePath: vi.fn().mockResolvedValue(null) });
    const response = await serveMedia({ owner: false, inviteToken, entryId, key }, deps);
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("Not Found");
    expect(response.headers.get("cache-control")).toContain("no-store");
  });

  it("hashes a valid invite cookie before server-side authorization", async () => {
    const invitePath = vi.fn().mockResolvedValue({ storage_path: storagePath, thumb_path: null });
    const response = await serveMedia(
      { owner: false, inviteToken, entryId, key },
      services({
        invitePath,
        signedUrl: vi.fn().mockResolvedValue("https://storage.test/signed"),
      }),
    );
    expect(response.status).toBe(302);
    expect(invitePath.mock.calls[0]?.[0]).not.toBe(inviteToken);
    expect(invitePath.mock.calls[0]?.[0]).toMatch(/^[a-f0-9]{64}$/);
  });

  it("returns generic 404 when signing fails", async () => {
    const response = await serveMedia(
      { owner: true, entryId, key },
      services({ ownerPath: vi.fn().mockResolvedValue({ storage_path: storagePath, thumb_path: null }) }),
    );
    expect(response.status).toBe(404);
    expect(await response.text()).toBe("Not Found");
  });
});

describe("video media", () => {
  it("signs a video for longer, so a URL cannot expire part-way through a clip", async () => {
    const videoPath = "r2:entries/e1/k1/v1.mp4";
    const deps = services({
      ownerPath: vi.fn().mockResolvedValue({ storage_path: videoPath, thumb_path: null }),
      signedUrl: vi.fn().mockResolvedValue("https://r2.test/signed"),
    });
    const response = await serveMedia({ owner: true, entryId, key }, deps);
    expect(response.status).toBe(302);
    expect(deps.signedUrl).toHaveBeenCalledWith(videoPath, VIDEO_URL_TTL_SECONDS);
    expect(VIDEO_URL_TTL_SECONDS).toBeGreaterThan(MEDIA_URL_TTL_SECONDS);
  });

  it("still refuses a video to a caller with no invite", async () => {
    const deps = services({ invitePath: vi.fn().mockResolvedValue(null) });
    const response = await serveMedia({ owner: false, inviteToken, entryId, key }, deps);
    expect(response.status).toBe(404);
    expect(deps.signedUrl).not.toHaveBeenCalled();
  });
});

describe("thumbnails", () => {
  const full = "entries/e1/k1/v1.jpg";
  const thumb = "entries/e1/k1/v1-thumb.jpg";

  function withThumbnail() {
    return services({
      ownerPath: vi.fn().mockResolvedValue({ storage_path: full, thumb_path: thumb }),
      signedUrl: vi.fn().mockResolvedValue("https://storage.test/signed"),
    });
  }

  it("serves the small copy when the grid asks for it", async () => {
    const deps = withThumbnail();
    await serveMedia({ owner: true, entryId, key, wantsThumbnail: true }, deps);
    expect(deps.signedUrl).toHaveBeenCalledWith(thumb, MEDIA_URL_TTL_SECONDS);
  });

  it("serves the original when opening the item", async () => {
    const deps = withThumbnail();
    await serveMedia({ owner: true, entryId, key }, deps);
    expect(deps.signedUrl).toHaveBeenCalledWith(full, MEDIA_URL_TTL_SECONDS);
  });

  /** Media published before thumbnails existed must still load. */
  it("falls back to the original when no small copy was made", async () => {
    const deps = services({
      ownerPath: vi.fn().mockResolvedValue({ storage_path: full, thumb_path: null }),
      signedUrl: vi.fn().mockResolvedValue("https://storage.test/signed"),
    });
    const response = await serveMedia({ owner: true, entryId, key, wantsThumbnail: true }, deps);
    expect(response.status).toBe(302);
    expect(deps.signedUrl).toHaveBeenCalledWith(full, MEDIA_URL_TTL_SECONDS);
  });

  /** A thumbnail is media too: asking for one must not skip authorization. */
  it("refuses a thumbnail to a caller with no access", async () => {
    const deps = services();
    const response = await serveMedia({ owner: false, entryId, key, wantsThumbnail: true }, deps);
    expect(response.status).toBe(404);
    expect(deps.signedUrl).not.toHaveBeenCalled();
  });
});
