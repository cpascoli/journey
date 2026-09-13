import { describe, expect, it } from "vitest";

import { ApiError } from "./errors";
import {
  asObject,
  dateField,
  dateTimeField,
  enumField,
  nullableString,
  numberField,
  parseUuid,
  queryInteger,
  stringField,
  uuidArrayField,
} from "./validate";

function field(run: () => unknown): string | undefined {
  try {
    run();
  } catch (error) {
    if (error instanceof ApiError) return String(error.details.field);
    throw error;
  }
  return undefined;
}

const uuid = "8B0B1E3C-7A1F-4C3B-9D9E-2F4A5B6C7D8E";

describe("validators", () => {
  it("accepts only JSON objects", () => {
    expect(asObject({ a: 1 })).toEqual({ a: 1 });
    expect(field(() => asObject([]))).toBe("body");
    expect(field(() => asObject(null, "location"))).toBe("location");
  });

  it("lowercases UUIDs and rejects anything else", () => {
    expect(parseUuid(uuid, "id")).toBe(uuid.toLowerCase());
    expect(field(() => parseUuid("not-a-uuid", "id"))).toBe("id");
  });

  it("applies string limits, requirements and fallbacks", () => {
    expect(stringField({}, "title", { max: 5 })).toBe("");
    expect(stringField({}, "journal", { max: 5, fallback: "Main" })).toBe("Main");
    expect(field(() => stringField({ title: "toolong" }, "title", { max: 5 }))).toBe("title");
    expect(field(() => stringField({ name: "  " }, "name", { max: 5, required: true }))).toBe("name");
    expect(field(() => stringField({ title: 3 }, "title", { max: 5 }))).toBe("title");
  });

  it("turns blank optional strings into null", () => {
    expect(nullableString({ place: "  Bangkok " }, "place", { max: 50 })).toBe("Bangkok");
    expect(nullableString({ place: "   " }, "place", { max: 50 })).toBeNull();
  });

  it("checks enums, with an optional fallback", () => {
    expect(enumField({}, "visibility", ["private", "shared"], "private")).toBe("private");
    expect(field(() => enumField({ visibility: "public" }, "visibility", ["private", "shared"]))).toBe(
      "visibility",
    );
  });

  it("normalises date-times to UTC and rejects plain dates", () => {
    expect(dateTimeField({ at: "2026-09-11T16:00:00+07:00" }, "at")).toBe("2026-09-11T09:00:00.000Z");
    expect(field(() => dateTimeField({ at: "2026-09-11" }, "at"))).toBe("at");
  });

  it("rejects impossible calendar dates", () => {
    expect(dateField({ day: "2026-09-11" }, "day")).toBe("2026-09-11");
    expect(field(() => dateField({ day: "2026-02-30" }, "day"))).toBe("day");
  });

  it("deduplicates UUID arrays and names the bad item", () => {
    expect(uuidArrayField({ tags: [uuid, uuid.toLowerCase()] }, "tags", { max: 5 })).toEqual([
      uuid.toLowerCase(),
    ]);
    expect(field(() => uuidArrayField({ tags: [uuid, "x"] }, "tags", { max: 5 }))).toBe("tags[1]");
  });

  it("bounds numbers and query integers", () => {
    expect(numberField({ lat: 13.7 }, "lat", { min: -90, max: 90 })).toBe(13.7);
    expect(field(() => numberField({ lat: 91 }, "lat", { min: -90, max: 90 }))).toBe("lat");
    expect(queryInteger(new URLSearchParams("width=2048"), "width", { min: 1, max: 10000 })).toBe(2048);
    expect(field(() => queryInteger(new URLSearchParams("width=1.5"), "width", { min: 1, max: 10 }))).toBe(
      "width",
    );
  });
});
