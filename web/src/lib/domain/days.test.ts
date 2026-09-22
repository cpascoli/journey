import { describe, expect, it } from "vitest";

import { dayOfMonth, groupDaysByMonth } from "./days";

describe("groupDaysByMonth", () => {
  const days = [
    { day: "2026-09-02", count: 1 },
    { day: "2026-09-20", count: 3 },
    { day: "2026-07-14", count: 2 },
    { day: "2026-09-12", count: 1 },
  ];

  it("groups by month, newest first", () => {
    expect(groupDaysByMonth(days).map((month) => month.month)).toEqual(["2026-09", "2026-07"]);
  });

  it("puts the newest day first inside a month", () => {
    expect(groupDaysByMonth(days)[0]?.days.map((entry) => entry.day)).toEqual([
      "2026-09-20",
      "2026-09-12",
      "2026-09-02",
    ]);
  });

  it("totals the entries in each month", () => {
    expect(groupDaysByMonth(days).map((month) => month.count)).toEqual([5, 2]);
  });

  /** Only days with something on them, so a gap costs nothing to render. */
  it("never invents a day that has no entries", () => {
    const months = groupDaysByMonth([{ day: "2026-09-20", count: 1 }]);
    expect(months[0]?.days).toHaveLength(1);
  });

  it("handles an empty journal", () => {
    expect(groupDaysByMonth([])).toEqual([]);
  });

  it("keeps days in different years apart", () => {
    const months = groupDaysByMonth([
      { day: "2025-09-20", count: 1 },
      { day: "2026-09-20", count: 1 },
    ]);
    expect(months.map((month) => month.month)).toEqual(["2026-09", "2025-09"]);
  });
});

describe("dayOfMonth", () => {
  it("reads the day number without a leading zero", () => {
    expect(dayOfMonth("2026-09-02")).toBe("2");
    expect(dayOfMonth("2026-09-20")).toBe("20");
  });
});
