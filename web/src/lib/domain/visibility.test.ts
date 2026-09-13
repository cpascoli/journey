import { describe, expect, it } from "vitest";

import { isVisibleToInvite } from "./visibility";

const family = "tag-family";
const sport = "tag-sport";
const dating = "tag-dating";

describe("isVisibleToInvite", () => {
  it("shows untagged shared entries to every invite, including one with no tags", () => {
    const entry = { visibility: "shared" as const, tagIds: [] };
    expect(isVisibleToInvite(entry, { tagIds: [] })).toBe(true);
    expect(isVisibleToInvite(entry, { tagIds: [family] })).toBe(true);
  });

  it("never shows private entries, whatever the invite allows", () => {
    const entry = { visibility: "private" as const, tagIds: [] };
    expect(isVisibleToInvite(entry, { tagIds: [family, sport, dating] })).toBe(false);
  });

  it("requires the invite to include every tag on the entry", () => {
    const entry = { visibility: "shared" as const, tagIds: [dating, sport] };
    expect(isVisibleToInvite(entry, { tagIds: [sport] })).toBe(false);
    expect(isVisibleToInvite(entry, { tagIds: [dating] })).toBe(false);
    expect(isVisibleToInvite(entry, { tagIds: [sport, dating] })).toBe(true);
    expect(isVisibleToInvite(entry, { tagIds: [sport, dating, family] })).toBe(true);
  });

  it("hides tagged entries from an invite with no tags", () => {
    const entry = { visibility: "shared" as const, tagIds: [family] };
    expect(isVisibleToInvite(entry, { tagIds: [] })).toBe(false);
  });

  it("shows nothing to a revoked invite", () => {
    const entry = { visibility: "shared" as const, tagIds: [] };
    expect(isVisibleToInvite(entry, { tagIds: [], revokedAt: "2026-09-13T10:00:00Z" })).toBe(
      false,
    );
  });
});
