import { describe, expect, it } from "vitest";

import { pageStart } from "./entries";

/** Newest first, as visibleEntries sorts them. */
const rows = [
  { id: "e5", day: "2026-09-20" },
  { id: "e4", day: "2026-09-18" },
  { id: "e3", day: "2026-09-18" },
  { id: "e2", day: "2026-09-18" },
  { id: "e1", day: "2026-09-02" },
];

describe("reader paging", () => {
  it("starts at the top with no cursor", () => {
    expect(pageStart(rows)).toBe(0);
    expect(pageStart(rows, "")).toBe(0);
  });

  it("resumes just after the entry the cursor names", () => {
    expect(pageStart(rows, "2026-09-18_e4")).toBe(2);
    expect(pageStart(rows, "2026-09-20_e5")).toBe(1);
  });

  /**
   * The reason the cursor names an entry and not just a day: three entries
   * share 2026-09-18, so a day-only cursor would jump past the two that had
   * not been shown yet.
   */
  it("does not skip entries that share the cursor's day", () => {
    const next = pageStart(rows, "2026-09-18_e4");
    expect(rows.slice(next).map((row) => row.id)).toEqual(["e3", "e2", "e1"]);
  });

  it("falls back to the next older day when the cursor's entry is gone", () => {
    const withoutE4 = rows.filter((row) => row.id !== "e4");
    // e3 and e2 are the same day and already seen, so an unpublished cursor
    // entry costs at most a repeat, never a silent skip.
    expect(withoutE4[pageStart(withoutE4, "2026-09-18_e4")]).toEqual({ id: "e1", day: "2026-09-02" });
  });

  it("reports the end when the cursor is older than everything", () => {
    expect(pageStart(rows, "2020-01-01_gone")).toBe(rows.length);
  });

  it("ignores a malformed cursor rather than failing", () => {
    expect(pageStart(rows, "nonsense")).toBe(0);
  });
});
