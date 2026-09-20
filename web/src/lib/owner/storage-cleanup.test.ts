import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, describe, expect, it, vi } from "vitest";

import { reconcileStorageCleanup, removeQueuedStorage } from "./storage-cleanup";

describe("storage cleanup", () => {
  it("keeps prequeued paths after failed object removals", async () => {
    const rpc = vi.fn().mockResolvedValue({ error: null });
    const remove = vi.fn().mockResolvedValue({ error: { code: "storage", message: "offline" } });
    const db = {
      storage: { from: vi.fn(() => ({ remove })) },
      rpc,
    } as unknown as SupabaseClient;

    await removeQueuedStorage(db, ["entries/e1/old.jpg", "entries/e1/old.jpg"]);

    expect(remove).toHaveBeenCalledWith(["entries/e1/old.jpg"]);
    expect(rpc).toHaveBeenCalledWith("finish_storage_cleanup", {
      p_storage_path: "entries/e1/old.jpg",
      p_removed: false,
      p_last_error: "storage: offline",
    });
  });

  it("claims only database-approved paths and finishes each attempt", async () => {
    const remove = vi.fn()
      .mockResolvedValueOnce({ error: null })
      .mockResolvedValueOnce({ error: { code: "storage", message: "still offline" } });
    const rpc = vi.fn()
      .mockResolvedValueOnce({
        data: [
          { storage_path: "gone.jpg", attempts: 0 },
          { storage_path: "retry.jpg", attempts: 2 },
        ],
        error: null,
      })
      .mockResolvedValue({ error: null });
    const db = {
      storage: { from: vi.fn(() => ({ remove })) },
      rpc,
    } as unknown as SupabaseClient;

    await expect(reconcileStorageCleanup(db)).resolves.toEqual({
      attempted: 2,
      removed: 1,
      failed: 1,
    });
    expect(rpc).toHaveBeenNthCalledWith(1, "claim_storage_cleanup", { p_limit: 100 });
    expect(rpc).toHaveBeenNthCalledWith(2, "finish_storage_cleanup", {
      p_storage_path: "gone.jpg",
      p_removed: true,
      p_last_error: null,
    });
    expect(rpc).toHaveBeenNthCalledWith(3, "finish_storage_cleanup", {
      p_storage_path: "retry.jpg",
      p_removed: false,
      p_last_error: "storage: still offline",
    });
  });
});

describe("storage cleanup across providers", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  function withR2() {
    vi.stubEnv("R2_ACCOUNT_ID", "account");
    vi.stubEnv("R2_ACCESS_KEY_ID", "key");
    vi.stubEnv("R2_SECRET_ACCESS_KEY", "secret");
    vi.stubEnv("R2_BUCKET", "journey-media");
  }

  it("deletes a video from R2 and never asks Supabase Storage for it", async () => {
    withR2();
    const fetchMock = vi.fn().mockResolvedValue(new Response(null, { status: 204 }));
    vi.stubGlobal("fetch", fetchMock);
    const rpc = vi.fn().mockResolvedValue({ error: null });
    const remove = vi.fn();
    const db = { storage: { from: vi.fn(() => ({ remove })) }, rpc } as unknown as SupabaseClient;

    await removeQueuedStorage(db, ["r2:entries/e1/k1/v1.mp4"]);

    expect(remove).not.toHaveBeenCalled();
    const [url, init] = fetchMock.mock.calls[0]!;
    expect(String(url)).toContain("account.r2.cloudflarestorage.com/journey-media/entries/e1/k1/v1.mp4");
    expect(init.method).toBe("DELETE");
    expect(rpc).toHaveBeenCalledWith("finish_storage_cleanup", {
      p_storage_path: "r2:entries/e1/k1/v1.mp4",
      p_removed: true,
      p_last_error: null,
    });
  });

  it("keeps an R2 object queued when the store refuses", async () => {
    withR2();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(null, { status: 500 })));
    const rpc = vi.fn().mockResolvedValue({ error: null });
    const db = {
      storage: { from: vi.fn(() => ({ remove: vi.fn() })) },
      rpc,
    } as unknown as SupabaseClient;

    await removeQueuedStorage(db, ["r2:entries/e1/k1/v1.mp4"]);

    expect(rpc).toHaveBeenCalledWith(
      "finish_storage_cleanup",
      expect.objectContaining({ p_removed: false }),
    );
  });

  it("still sends a photo path to Supabase Storage", async () => {
    withR2();
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const remove = vi.fn().mockResolvedValue({ error: null });
    const db = {
      storage: { from: vi.fn(() => ({ remove })) },
      rpc: vi.fn().mockResolvedValue({ error: null }),
    } as unknown as SupabaseClient;

    await removeQueuedStorage(db, ["entries/e1/k1/p1.jpg"]);

    expect(remove).toHaveBeenCalledWith(["entries/e1/k1/p1.jpg"]);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
