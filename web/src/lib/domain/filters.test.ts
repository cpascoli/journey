import { describe, expect, it } from "vitest";

import {
  filterEntries,
  hasActiveFilters,
  matchesQuery,
  normalise,
  parseQuery,
  parseTimeframe,
  tagFacets,
  timeframeStart,
  type Filters,
} from "./filters";

const now = new Date("2026-09-21T12:00:00Z");

const family = { id: "f1", name: "Family" };
const sport = { id: "f2", name: "Sport" };

type Row = { id: string; day: string; tags: { id: string; name: string }[]; text: string };

const entries: Row[] = [
  { id: "a", day: "2026-09-20", tags: [family], text: "The river was warm at dusk" },
  { id: "b", day: "2026-09-10", tags: [family, sport], text: "Climbing above the città" },
  { id: "c", day: "2026-07-01", tags: [sport], text: "A long ride" },
  { id: "d", day: "2026-09-19", tags: [], text: "Untagged and recent" },
];

const noFilters: Filters = { tag: null, timeframe: "all", query: "" };
const text = (entry: Row) => [entry.text];

describe("parsing reader-supplied filters", () => {
  it("accepts only the timeframes it has, defaulting to all", () => {
    expect(parseTimeframe("week")).toBe("week");
    expect(parseTimeframe("month")).toBe("month");
    expect(parseTimeframe("decade")).toBe("all");
    expect(parseTimeframe(null)).toBe("all");
  });

  it("trims a query and caps its length", () => {
    expect(parseQuery("  river  ")).toBe("river");
    expect(parseQuery(null)).toBe("");
    expect(parseQuery("x".repeat(500))).toHaveLength(100);
  });
});

describe("timeframeStart", () => {
  it("counts back from today", () => {
    expect(timeframeStart("week", now)).toBe("2026-09-14");
    expect(timeframeStart("month", now)).toBe("2026-08-22");
  });

  it("has no start for all time", () => {
    expect(timeframeStart("all", now)).toBeNull();
  });
});

describe("matchesQuery", () => {
  it("ignores case and accents, so an English keyboard finds Italian words", () => {
    expect(normalise("Città")).toBe("citta");
    expect(matchesQuery(["Climbing above the città"], "citta")).toBe(true);
    expect(matchesQuery(["Climbing above the città"], "CITTÀ")).toBe(true);
  });

  it("requires every word, in any order", () => {
    expect(matchesQuery(["The river was warm at dusk"], "dusk river")).toBe(true);
    expect(matchesQuery(["The river was warm at dusk"], "river mountain")).toBe(false);
  });

  it("matches nothing in particular when the query is empty", () => {
    expect(matchesQuery(["anything"], "   ")).toBe(true);
  });

  it("does not match across separate fields as if they were one phrase", () => {
    expect(matchesQuery(["Temple of Dawn", "a quiet morning"], "dawn a")).toBe(true);
    expect(matchesQuery(["Temple", "Dawn"], "templedawn")).toBe(false);
  });
});

describe("tagFacets", () => {
  it("offers only tags that appear on the entries given, with counts", () => {
    expect(tagFacets(entries)).toEqual([
      { id: "f1", name: "Family", count: 2 },
      { id: "f2", name: "Sport", count: 2 },
    ]);
  });

  /**
   * The list is built from visible entries, never from the tags table, so a
   * tag this reader cannot see cannot appear — and neither can one with no
   * entries left after an unpublish.
   */
  it("cannot surface a tag with no visible entries", () => {
    const visible = entries.filter((entry) => entry.tags.some((tag) => tag.id === "f1"));
    expect(tagFacets(visible).map((facet) => facet.id)).toEqual(["f1", "f2"]);
    expect(tagFacets([{ day: "2026-09-01", tags: [] }])).toEqual([]);
  });

  it("puts the commonest first, then alphabetical", () => {
    const rows = [
      { day: "2026-09-01", tags: [sport] },
      { day: "2026-09-02", tags: [sport] },
      { day: "2026-09-03", tags: [family] },
    ];
    expect(tagFacets(rows).map((facet) => facet.name)).toEqual(["Sport", "Family"]);
  });
});

describe("filterEntries", () => {
  it("returns everything when nothing is set", () => {
    expect(filterEntries(entries, noFilters, text, now)).toHaveLength(4);
  });

  it("filters by tag", () => {
    const result = filterEntries(entries, { ...noFilters, tag: "f2" }, text, now);
    expect(result.map((entry) => entry.id)).toEqual(["b", "c"]);
  });

  it("filters by timeframe on the writer's calendar day", () => {
    const week = filterEntries(entries, { ...noFilters, timeframe: "week" }, text, now);
    expect(week.map((entry) => entry.id)).toEqual(["a", "d"]);
    const month = filterEntries(entries, { ...noFilters, timeframe: "month" }, text, now);
    expect(month.map((entry) => entry.id)).toEqual(["a", "b", "d"]);
  });

  it("filters by search", () => {
    const result = filterEntries(entries, { ...noFilters, query: "river" }, text, now);
    expect(result.map((entry) => entry.id)).toEqual(["a"]);
  });

  it("combines filters rather than choosing between them", () => {
    const result = filterEntries(
      entries,
      { tag: "f1", timeframe: "month", query: "citta" },
      text,
      now,
    );
    expect(result.map((entry) => entry.id)).toEqual(["b"]);
  });

  /** Filtering is presentation; it must never be able to add an entry. */
  it("can only ever narrow what it was given", () => {
    const result = filterEntries(entries, { tag: "nonexistent", timeframe: "all", query: "" }, text, now);
    expect(result).toEqual([]);
    expect(entries).toHaveLength(4);
  });
});

describe("hasActiveFilters", () => {
  it("knows when a reader has narrowed the journal", () => {
    expect(hasActiveFilters(noFilters)).toBe(false);
    expect(hasActiveFilters({ ...noFilters, tag: "f1" })).toBe(true);
    expect(hasActiveFilters({ ...noFilters, timeframe: "week" })).toBe(true);
    expect(hasActiveFilters({ ...noFilters, query: "river" })).toBe(true);
  });
});
