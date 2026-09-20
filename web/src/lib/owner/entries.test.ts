import { describe, expect, it } from "vitest";

import { ApiError } from "@/lib/api/errors";

import { parseEntryWrite } from "./entries";

const tag = "6a1f0c2e-1b2c-4d3e-8f9a-0b1c2d3e4f5a";

const base = {
  occurred_at: "2026-09-11T09:00:00+07:00",
  day: "2026-09-11",
  title: "Temple of Dawn",
  notes: "Climbed the central prang before the crowds.",
  location: { place_name: "Wat Arun", locality: "Bangkok", latitude: 13.743712, longitude: 100.488921 },
};

function codeOf(run: () => unknown): string | undefined {
  try {
    run();
  } catch (error) {
    return error instanceof ApiError ? `${error.code}:${String(error.details.field)}` : "OTHER";
  }
  return undefined;
}

describe("parseEntryWrite", () => {
  it("defaults to private, city precision and the Main journal", () => {
    const { fields, tagIds, mediaKeys } = parseEntryWrite(base);
    expect(fields.visibility).toBe("private");
    expect(fields.location_precision).toBe("city");
    expect(fields.journal_name).toBe("Main");
    expect(fields.narrative_source).toBe("user");
    expect(fields.occurred_at).toBe("2026-09-11T02:00:00.000Z");
    expect(fields.client_content_hash).toBeNull();
    expect(tagIds).toEqual([]);
    expect(mediaKeys).toBeNull();
  });

  it("reduces the location to its precision before it is stored", () => {
    const city = parseEntryWrite(base).fields;
    expect([city.place_name, city.latitude, city.longitude]).toEqual(["Bangkok", 13.7, 100.5]);
    const hidden = parseEntryWrite({ ...base, location_precision: "hidden" }).fields;
    expect([hidden.place_name, hidden.latitude, hidden.longitude]).toEqual([null, null, null]);
    const exact = parseEntryWrite({ ...base, location_precision: "exact" }).fields;
    expect([exact.place_name, exact.latitude]).toEqual(["Wat Arun", 13.743712]);
  });

  it("passes tags, translation and media keys through, deduplicated", () => {
    const write = parseEntryWrite({
      ...base,
      visibility: "shared",
      tag_ids: [tag, tag.toUpperCase()],
      translation: { language: "it", title: "Tempio dell'Alba", notes: "", narrative: "" },
      media_keys: ["abc", "def", "abc"],
      client_content_hash: "a".repeat(64),
    });
    expect(write.fields.visibility).toBe("shared");
    expect(write.tagIds).toEqual([tag]);
    expect(write.fields.translation_language).toBe("it");
    expect(write.fields.translated_title).toBe("Tempio dell'Alba");
    expect(write.fields.client_content_hash).toBe("a".repeat(64));
    expect(write.mediaKeys).toEqual(["abc", "def"]);
  });

  it("rejects bad fields by name", () => {
    expect(codeOf(() => parseEntryWrite({ ...base, day: "11/09/2026" }))).toBe("VALIDATION_ERROR:day");
    expect(codeOf(() => parseEntryWrite({ ...base, visibility: "public" }))).toBe(
      "VALIDATION_ERROR:visibility",
    );
    expect(codeOf(() => parseEntryWrite({ ...base, location: { latitude: 200 } }))).toBe(
      "VALIDATION_ERROR:latitude",
    );
    expect(codeOf(() => parseEntryWrite({ ...base, media_keys: ["a/b"] }))).toBe(
      "VALIDATION_ERROR:media_keys[0]",
    );
    expect(codeOf(() => parseEntryWrite({ ...base, client_content_hash: "A".repeat(64) }))).toBe(
      "VALIDATION_ERROR:client_content_hash",
    );
    expect(codeOf(() => parseEntryWrite({ ...base, translation: { title: "x" } }))).toBe(
      "VALIDATION_ERROR:language",
    );
  });
});
